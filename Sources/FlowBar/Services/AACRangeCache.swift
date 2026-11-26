import Foundation

enum AACRangeError: LocalizedError {
    case invalidResponse
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The audio server did not return the requested byte range."
        case .invalidFile: return "Could not read the temporary audio file."
        }
    }
}

struct AACHTTPSource: Decodable {
    let url: URL
    let headers: [String: String]

    enum CodingKeys: String, CodingKey {
        case url
        case headers = "http_headers"
    }

    func open(in directory: URL) async throws -> AACRangeCache {
        let range: Range<Int64> = 0..<2
        let (data, length) = try await fetch(range)
        guard data.count == 2, length > 2 else { throw AACRangeError.invalidResponse }
        return try AACRangeCache(length: length, directory: directory) { range in
            let (data, reportedLength) = try await fetch(range)
            guard reportedLength == length else { throw AACRangeError.invalidResponse }
            return data
        }
    }

    private func fetch(_ range: Range<Int64>) async throws -> (Data, Int64) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        for header in ["User-Agent", "Accept", "Accept-Language", "Referer", "Origin"] {
            request.setValue(headers.first { $0.key.caseInsensitiveCompare(header) == .orderedSame }?.value,
                             forHTTPHeaderField: header)
        }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AACRangeTransport.session.data(for: request)
        } catch let error as URLError where error.code == .cancelled && !Task.isCancelled {
            // The response delegate rejects invalid ranges before reading the body.
            throw AACRangeError.invalidResponse
        }
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 206,
              let length = AACRangeCache.totalLength(in: response.value(forHTTPHeaderField: "Content-Range"), matching: range),
              data.count == range.count else { throw AACRangeError.invalidResponse }
        return (data, length)
    }
}

private final class AACRangeTransport: NSObject, URLSessionDataDelegate {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration, delegate: AACRangeTransport(), delegateQueue: nil)
    }()

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // Refuse an unexpected full response before URLSession allocates a buffer for it.
        let requested = dataTask.originalRequest?.value(forHTTPHeaderField: "Range")
        guard let response = response as? HTTPURLResponse, response.statusCode == 206,
              let requested, requested.hasPrefix("bytes="),
              let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
              contentRange.hasPrefix("bytes \(requested.dropFirst(6))/") else {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }
}

actor AACRangeCache {
    nonisolated let length: Int64

    private let blockSize: Int64
    private let temporary: URL
    private let file: FileHandle
    private let fetch: @Sendable (Range<Int64>) async throws -> Data
    private let retryDelays: [Duration]
    private var available: Set<Int64> = []
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Void, Error>]
    }
    private var inFlight: [Int64: Flight] = [:]
    private var receivedBytes: Int64 = 0
    private(set) var isComplete = false

    init(length: Int64, directory: URL, blockSize: Int64 = 1_048_576,
         retryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16)],
         fetch: @escaping @Sendable (Range<Int64>) async throws -> Data) throws {
        precondition(length > 0 && blockSize > 0)
        self.length = length
        self.blockSize = blockSize
        self.fetch = fetch
        self.retryDelays = retryDelays
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".aac-part")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw AACRangeError.invalidFile
        }
        do {
            file = try FileHandle(forUpdating: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        self.temporary = temporary
    }

    deinit {
        try? file.close()
        try? FileManager.default.removeItem(at: temporary)
    }

    static func totalLength(in header: String?, matching range: Range<Int64>) -> Int64? {
        let prefix = "bytes \(range.lowerBound)-\(range.upperBound - 1)/"
        guard let header, header.hasPrefix(prefix),
              let total = Int64(header.dropFirst(prefix.count)), total >= range.upperBound else { return nil }
        return total
    }

    func read(at offset: Int64, through end: Int64) async throws -> Data {
        guard offset >= 0, offset < min(end, length) else { return Data() }
        let bounds = try await ensureBlock(offset / blockSize)
        try Task.checkCancellation()
        try file.seek(toOffset: UInt64(offset))
        let size = Int(min(end, bounds.upperBound) - offset)
        guard let data = try file.read(upToCount: size), data.count == size else { throw AACRangeError.invalidFile }
        return data
    }

    func fill(destination: URL, progress: @Sendable (Double) -> Void) async throws {
        let blocks = (length - 1) / blockSize + 1
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<min(4, blocks) {
                group.addTask { _ = try await self.ensureBlock(index) }
            }
            var index: Int64 = min(4, blocks)
            while try await group.next() != nil {
                try Task.checkCancellation()
                progress(Double(receivedBytes) / Double(length))
                if index < blocks {
                    let next = index
                    group.addTask { _ = try await self.ensureBlock(next) }
                    index += 1
                }
            }
        }
        try Task.checkCancellation()
        try file.synchronize()
        if rename(temporary.path, destination.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        isComplete = true
        DiagnosticsLogger.shared.log(level: "info", message: "AAC cache received \(receivedBytes) media bytes")
    }

    private func ensureBlock(_ index: Int64) async throws -> Range<Int64> {
        try Task.checkCancellation()
        let lower = index * blockSize
        let range = lower..<(lower + min(blockSize, length - lower))
        guard !available.contains(index) else { return range }
        let waiter = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if inFlight[index] != nil {
                    inFlight[index]?.waiters[waiter] = continuation
                } else {
                    let id = UUID()
                    let task = Task {
                        do {
                            let data = try await fetchWithRetry(range)
                            finishBlock(index, id: id, range: range, result: .success(data))
                        } catch {
                            finishBlock(index, id: id, range: range, result: .failure(error))
                        }
                    }
                    inFlight[index] = Flight(id: id, task: task, waiters: [waiter: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiter, in: index) }
        }
        try Task.checkCancellation()
        return range
    }

    private func cancelWaiter(_ waiter: UUID, in index: Int64) {
        guard let continuation = inFlight[index]?.waiters.removeValue(forKey: waiter) else { return }
        if inFlight[index]?.waiters.isEmpty == true {
            inFlight.removeValue(forKey: index)?.task.cancel()
        }
        continuation.resume(throwing: CancellationError())
    }

    private func finishBlock(_ index: Int64, id: UUID, range: Range<Int64>, result: Result<Data, Error>) {
        guard inFlight[index]?.id == id, let flight = inFlight.removeValue(forKey: index) else { return }
        let written = Result {
            let data = try result.get()
            guard data.count == range.count else { throw AACRangeError.invalidResponse }
            try file.seek(toOffset: UInt64(range.lowerBound))
            try file.write(contentsOf: data)
            available.insert(index)
            receivedBytes += Int64(data.count)
        }
        for waiter in flight.waiters.values {
            waiter.resume(with: written)
        }
    }

    private func fetchWithRetry(_ range: Range<Int64>) async throws -> Data {
        for delay in retryDelays {
            try Task.checkCancellation()
            do {
                return try await fetch(range)
            } catch let error as URLError where Self.isTemporaryNetworkError(error) {
                try await Task.sleep(for: delay)
            }
        }
        try Task.checkCancellation()
        return try await fetch(range)
    }

    private static func isTemporaryNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}
