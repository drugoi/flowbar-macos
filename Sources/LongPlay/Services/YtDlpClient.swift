import Foundation

enum YtDlpError: LocalizedError {
    case notInstalled
    case executionFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "yt-dlp is not installed or not found in PATH."
        case .executionFailed(let message):
            return YtDlpError.userFacingMessage(from: message)
        case .invalidOutput:
            return "yt-dlp returned unexpected output."
        }
    }

    private static func userFacingMessage(from output: String) -> String {
        let lowercased = output.lowercased()
        if lowercased.contains("no space left on device") {
            return "Not enough disk space to complete the download."
        }
        if lowercased.contains("video unavailable")
            || lowercased.contains("this video is unavailable")
            || lowercased.contains("private video")
            || lowercased.contains("members-only")
            || lowercased.contains("sign in to confirm") {
            return "Video unavailable or restricted."
        }
        if lowercased.contains("http error 429") || lowercased.contains("too many requests") {
            return "YouTube rate-limited the request. Try again later."
        }
        if lowercased.contains("unable to download") || lowercased.contains("failed to download") {
            return "Download failed. Check your connection and try again."
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "yt-dlp failed for an unknown reason."
        }
        return "yt-dlp failed: \(trimmed)"
    }
}

struct YtDlpMetadata: Equatable {
    let title: String
    let durationSeconds: Double?
}

struct YtDlpClient {
    let executable: String

    init(executable: String = "yt-dlp") {
        self.executable = executable
    }

    static let minimumSupportedVersion = "2024.01.01"

    private var bundledExecutableURL: URL? {
        Bundle.main.url(forResource: "yt-dlp", withExtension: nil, subdirectory: "bin")
    }

    private var bundledFfmpegDirectory: URL? {
        Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "bin")
            .map { $0.deletingLastPathComponent() }
    }

    private var bundledDenoURL: URL? {
        Bundle.main.url(forResource: "deno", withExtension: nil, subdirectory: "bin")
    }

    func isAvailable() -> Bool {
        if let bundled = bundledExecutableURL {
            if !FileManager.default.fileExists(atPath: bundled.path) {
                DiagnosticsLogger.shared.log(level: "error", message: "yt-dlp missing at \(bundled.path)")
                return false
            }
            if !FileManager.default.isExecutableFile(atPath: bundled.path) {
                DiagnosticsLogger.shared.log(level: "warning", message: "yt-dlp not executable, attempting to fix permissions.")
                do {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)
                } catch {
                    DiagnosticsLogger.shared.log(level: "error", message: "Failed to chmod yt-dlp: \(error.localizedDescription)")
                }
            }
            do {
                _ = try runSync(executableURL: bundled, args: ["--version"])
                return true
            } catch {
                DiagnosticsLogger.shared.log(level: "error", message: "yt-dlp execution failed: \(error.localizedDescription)")
                return false
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable, "--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    func fetchVersion() -> String? {
        if let bundled = bundledExecutableURL {
            do {
                return try runSync(executableURL: bundled, args: ["--version"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                DiagnosticsLogger.shared.log(level: "error", message: "yt-dlp version check failed: \(error.localizedDescription)")
                return nil
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable, "--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isVersionOutdated(_ version: String) -> Bool {
        guard let current = Self.parseVersionDate(version),
              let minimum = Self.parseVersionDate(Self.minimumSupportedVersion) else {
            return true
        }
        return current < minimum
    }

    func isFfmpegAvailable() -> Bool {
        guard let dir = bundledFfmpegDirectory else { return false }
        let ffmpeg = dir.appendingPathComponent("ffmpeg").path
        let ffprobe = dir.appendingPathComponent("ffprobe").path
        return FileManager.default.fileExists(atPath: ffmpeg)
            && FileManager.default.fileExists(atPath: ffprobe)
    }

    func resolveMetadata(url: URL) async throws -> YtDlpMetadata {
        let args = baseArgs(playerClients: "web") + [
            "--print", "%(title)s",
            "--print", "%(duration)s",
            "--skip-download",
            "--quiet",
            "--no-playlist",
            "--socket-timeout", "8",
            "--retries", "1",
            "--no-warnings",
            url.absoluteString
        ]
        let output = try await run(args)
        let parsedLines = output
            .split(separator: "\n")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if line.hasPrefix("WARNING:") || line.hasPrefix("[") || line.hasPrefix("ERROR:") {
                    return false
                }
                return true
            }
        guard let title = parsedLines.first, !title.isEmpty else {
            throw YtDlpError.invalidOutput
        }
        let durationLine = parsedLines.dropFirst().first
        let durationValue = durationLine.flatMap { line in
            let lowercased = line.lowercased()
            guard !lowercased.isEmpty, lowercased != "na", lowercased != "none" else {
                return nil
            }
            return Double(lowercased)
        }
        return YtDlpMetadata(title: title, durationSeconds: durationValue)
    }

    func fetchTitleFallback(url: URL) async -> String? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/oembed"
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let oembedURL = components.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: oembedURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            struct OEmbedResponse: Decodable { let title: String }
            let decoded = try JSONDecoder().decode(OEmbedResponse.self, from: data)
            let trimmed = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    func downloadAudio(url: URL, destinationURL: URL, progress: @escaping (Double?) -> Void) async throws {
        var args = baseArgs(playerClients: "web,web_safari,android") + [
            "-x",
            "--audio-format", "m4a",
            "--audio-quality", "0",
            "--postprocessor-args", "ffmpeg:-ac 2 -ar 44100 -b:a 320k",
            "--no-playlist",
            "--no-part",
            "--no-continue",
            "--newline",
            "-f", "bestaudio[ext=m4a]/bestaudio[ext=mp4]/bestaudio/best",
            "-o", destinationURL.path,
            url.absoluteString
        ]
        if let ffmpegDir = bundledFfmpegDirectory {
            args.insert(contentsOf: ["--ffmpeg-location", ffmpegDir.path], at: 0)
        }
        _ = try await run(args, progress: progress)
    }

    func fetchStreamURL(url: URL) async throws -> URL {
        let preferredFormats = [
            "bestaudio[acodec^=mp4a][ext=m4a]",
            "bestaudio[acodec^=mp4a][ext=mp4]",
            "bestaudio[acodec^=mp4a][protocol^=https]"
        ]
        for format in preferredFormats {
            do {
                return try await fetchStreamURL(url: url, format: format)
            } catch {
                continue
            }
        }
        throw YtDlpError.invalidOutput
    }

    private func fetchStreamURL(url: URL, format: String?) async throws -> URL {
        var args = baseArgs(playerClients: "web,web_safari,android") + [
            "-g",
            "--no-playlist",
            url.absoluteString
        ]
        if let format {
            args.insert(contentsOf: ["-f", format], at: 0)
        }
        let output = try await run(args)
        let lines = output.split(separator: "\n").map(String.init)
        guard let line = lines.first(where: { $0.hasPrefix("http") || $0.hasPrefix("https") }),
              let streamURL = URL(string: line.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw YtDlpError.invalidOutput
        }
        return streamURL
    }

    private func baseArgs(playerClients: String) -> [String] {
        var args = ["--extractor-args", "youtube:player_client=\(playerClients)"]
        if let denoURL = bundledDenoURL {
            args.append(contentsOf: ["--js-runtimes", "deno:\(denoURL.path)"])
        }
        return args
    }

    private func run(_ args: [String], progress: ((Double?) -> Void)? = nil) async throws -> String {
        let process = Process()
        if let bundled = bundledExecutableURL {
            process.executableURL = bundled
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + args
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withTaskCancellationHandler(operation: {
            do {
                try process.run()
            } catch {
                throw YtDlpError.notInstalled
            }

            var output = ""
            let outputQueue = DispatchQueue(label: "longplay.ytdlp.output")

            let outputHandle = stdout.fileHandleForReading
            let errorHandle = stderr.fileHandleForReading

            outputHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                outputQueue.async {
                    output.append(chunk)
                }
                if let progress = progress {
                    chunk.split(separator: "\n").forEach { line in
                        if let value = parseProgress(line: String(line)) {
                            progress(value)
                        }
                    }
                }
            }

            errorHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                outputQueue.async {
                    output.append(chunk)
                }
            }

            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { proc in
                    outputHandle.readabilityHandler = nil
                    errorHandle.readabilityHandler = nil
                    outputQueue.async {
                        if proc.terminationStatus == 0 {
                            continuation.resume(returning: output)
                        } else {
                            continuation.resume(throwing: YtDlpError.executionFailed(output))
                        }
                    }
                }
            }
        }
        , onCancel: {
            process.terminate()
        })
    }

    private func runSync(executableURL: URL, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw YtDlpError.executionFailed(output)
        }
        return output
    }

    private static func parseVersionDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseProgress(line: String) -> Double? {
        guard line.contains("[download]") else { return nil }
        let pattern = "\\[download\\]\\s+([0-9.]+)%"
        guard let match = line.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(line[match])
        let numberPattern = "([0-9.]+)"
        guard let valueRange = matched.range(of: numberPattern, options: .regularExpression) else { return nil }
        let valueString = String(matched[valueRange])
        return Double(valueString).map { $0 / 100.0 }
    }
}
