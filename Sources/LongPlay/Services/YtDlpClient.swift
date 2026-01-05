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

    func isAvailable() -> Bool {
        if let bundled = bundledExecutableURL {
            return (try? runSync(executableURL: bundled, args: ["--version"])) != nil
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
            return try? runSync(executableURL: bundled, args: ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
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
        let args = baseArgs() + [
            "--dump-json",
            "--no-playlist",
            "--socket-timeout", "10",
            "--retries", "1",
            "--no-warnings",
            url.absoluteString
        ]
        let output = try await run(args)
        guard let data = output.data(using: .utf8) else {
            throw YtDlpError.invalidOutput
        }
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let title = decoded?["title"] as? String else {
            throw YtDlpError.invalidOutput
        }
        let durationSeconds = decoded?["duration"] as? Double
        return YtDlpMetadata(title: title, durationSeconds: durationSeconds)
    }

    func downloadAudio(url: URL, destinationURL: URL, progress: @escaping (Double?) -> Void) async throws {
        var args = baseArgs() + [
            "-x",
            "--audio-format", "m4a",
            "--audio-quality", "0",
            "--no-playlist",
            "--newline",
            "-o", destinationURL.path,
            url.absoluteString
        ]
        if let ffmpegDir = bundledFfmpegDirectory {
            args.insert(contentsOf: ["--ffmpeg-location", ffmpegDir.path], at: 0)
        }
        _ = try await run(args, progress: progress)
    }

    private func baseArgs() -> [String] {
        [
            "--extractor-args", "youtube:player_client=android"
        ]
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

        return try await withTaskCancellationHandler {
            process.terminate()
        } operation: {
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
        guard process.terminationStatus == 0 else {
            throw YtDlpError.executionFailed("")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
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
