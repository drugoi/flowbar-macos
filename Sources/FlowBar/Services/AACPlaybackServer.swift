import Foundation
import Network

struct AACFragmentIndex {
    struct Segment {
        let bytes: Range<Int64>
        let duration: Double
    }

    let initialization: Range<Int64>
    let segments: [Segment]

    init?(data: Data, length: Int64) {
        func uint32(_ offset: Int) -> UInt32 {
            data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
        }
        guard data.count >= 8 else { return nil }
        var offset = 0
        var hasMovie = false
        while offset <= data.count - 8 {
            let size = Int(uint32(offset))
            guard size >= 8, size <= data.count - offset else { return nil }
            let kind = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if kind == "moov" { hasMovie = true }
            if kind == "sidx" { break }
            offset += size
        }
        guard hasMovie, offset <= data.count - 32 else { return nil }
        let size = Int(uint32(offset))
        guard size >= 32, size <= data.count - offset else { return nil }
        let end = offset + size
        let version = data[offset + 8]
        let timescale = uint32(offset + 16)
        guard timescale > 0, version <= 1, size >= (version == 0 ? 32 : 40) else { return nil }
        let firstOffset = version == 0
            ? UInt64(uint32(offset + 24))
            : UInt64(uint32(offset + 28)) << 32 | UInt64(uint32(offset + 32))
        let countPosition = offset + (version == 0 ? 28 : 36)
        let count = Int(uint32(countPosition) & 0xffff)
        guard count > 0, count <= (end - countPosition - 4) / 12,
              firstOffset <= UInt64(max(0, length - Int64(end))) else { return nil }

        var start = Int64(end) + Int64(firstOffset)
        var segments: [Segment] = []
        for i in 0..<count {
            let position = countPosition + 4 + i * 12
            let reference = uint32(position)
            let duration = uint32(position + 4)
            guard reference > 0, reference <= 8_388_608, duration > 0,
                  Int64(reference) <= length - start else { return nil }
            let next = start + Int64(reference)
            segments.append(Segment(bytes: start..<next, duration: Double(duration) / Double(timescale)))
            start = next
        }
        self.initialization = 0..<Int64(offset)
        self.segments = segments
    }

    var playlist: Data {
        let longest = segments.map(\.duration).max() ?? 1
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(Int(ceil(longest)))",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXT-X-MAP:URI=\"init.mp4\""
        ]
        for (index, segment) in segments.enumerated() {
            lines.append("#EXTINF:\(segment.duration),")
            lines.append("\(index).m4s")
        }
        lines.append("#EXT-X-ENDLIST")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}

final class AACPlaybackServer: @unchecked Sendable {
    let cache: AACRangeCache
    private let index: AACFragmentIndex
    private let playlist: Data
    private let listener: NWListener
    private let queue = DispatchQueue(label: "flowbar.aac.hls")

    static func open(cache: AACRangeCache) async throws -> (server: AACPlaybackServer, url: URL) {
        let head = try await cache.read(at: 0, through: min(cache.length, 1_048_576))
        guard let index = AACFragmentIndex(data: head, length: cache.length) else { throw AACRangeError.invalidFile }
        let server = try AACPlaybackServer(cache: cache, index: index)
        let port = try await server.start()
        try Task.checkCancellation()
        guard let url = URL(string: "http://127.0.0.1:\(port)/audio.m3u8") else { throw AACRangeError.invalidFile }
        return (server, url)
    }

    private init(cache: AACRangeCache, index: AACFragmentIndex) throws {
        self.cache = cache
        self.index = index
        self.playlist = index.playlist
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    private func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 75) { connection.cancel() }
                self.receive(connection, header: Data())
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    if let port = self.listener.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: AACRangeError.invalidFile)
                    }
                case .failed(let error), .waiting(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func receive(_ connection: NWConnection, header: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, done, error in
            guard let self, error == nil, let data else { connection.cancel(); return }
            let header = header + data
            if let boundary = header.range(of: Data("\r\n\r\n".utf8)), boundary.lowerBound <= 8_192 {
                let text = String(decoding: header[..<boundary.lowerBound], as: UTF8.self)
                self.respond(connection, request: text)
            } else if done || header.count >= 8_192 {
                connection.cancel()
            } else {
                self.receive(connection, header: header)
            }
        }
    }

    private func respond(_ connection: NWConnection, request: String) {
        let line = request.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard line.count == 3, line[0] == "GET" || line[0] == "HEAD" else {
            send(connection, status: "400 Bad Request")
            return
        }
        let headersOnly = line[0] == "HEAD"
        let path = line[1]
        if path == "/audio.m3u8" {
            send(connection, status: "200 OK", type: "application/vnd.apple.mpegurl",
                 body: playlist, headersOnly: headersOnly)
            return
        }

        let range: Range<Int64>
        if path == "/init.mp4" {
            range = index.initialization
        } else if path.hasPrefix("/"), path.hasSuffix(".m4s"),
                  let position = Int(path.dropFirst().dropLast(4)), index.segments.indices.contains(position) {
            range = index.segments[position].bytes
        } else {
            send(connection, status: "404 Not Found")
            return
        }
        if headersOnly {
            send(connection, status: "200 OK", type: "audio/mp4", contentLength: range.count, headersOnly: true)
            return
        }
        let transfer = Task {
            do {
                var data = Data()
                var offset = range.lowerBound
                while offset < range.upperBound {
                    let chunk = try await cache.read(at: offset, through: range.upperBound)
                    guard !chunk.isEmpty else { throw AACRangeError.invalidFile }
                    data.append(chunk)
                    offset += Int64(chunk.count)
                }
                send(connection, status: "200 OK", type: "audio/mp4", body: data)
            } catch {
                send(connection, status: "502 Bad Gateway")
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: transfer.cancel()
            default: break
            }
        }
    }

    private func send(_ connection: NWConnection, status: String, type: String = "text/plain",
                      body: Data = Data(), contentLength: Int? = nil, headersOnly: Bool = false) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(contentLength ?? body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + (headersOnly ? Data() : body), contentContext: .finalMessage,
                        isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    deinit { listener.cancel() }
}
