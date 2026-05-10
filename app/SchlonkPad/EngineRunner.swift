import Foundation

enum DownloadEvent {
    case metadata(title: String, durationSeconds: Double?, thumbnailURL: URL?)
    case progress(percent: Double)
    case finished(file: URL)
    case failed(message: String)
}

/// Wraps the bundled yt-dlp_macos binary as a subprocess and surfaces lifecycle
/// events via an AsyncStream. Stays format-agnostic — yt-dlp picks the best
/// progressive format by default.
final class EngineRunner {

    enum Error: Swift.Error, LocalizedError {
        case binaryMissing
        var errorDescription: String? {
            switch self {
            case .binaryMissing: return "yt-dlp_macos not found in app bundle"
            }
        }
    }

    private let executable: URL

    init() throws {
        guard let url = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) else {
            throw Error.binaryMissing
        }
        self.executable = url
    }

    func download(urlString: String, outputDir: URL) -> AsyncStream<DownloadEvent> {
        let executable = self.executable

        return AsyncStream { continuation in
            let process = Process()
            process.executableURL = executable

            let outputTemplate = outputDir
                .appendingPathComponent("%(title).200B [%(id)s].%(ext)s")
                .path
            process.arguments = [
                "--newline",
                "--no-warnings",
                "--no-playlist",
                "--no-mtime",
                "-o", outputTemplate,
                "--print", "before_dl:META %(.{title,duration,thumbnail})j",
                "--print", "after_video:DONE %(filepath)s",
                urlString,
            ]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let outBuffer = LineBuffer()
            let errBuffer = LockedData()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let chunk = String(data: data, encoding: .utf8) {
                    for line in outBuffer.feed(chunk) {
                        if let event = Self.parseLine(line) {
                            continuation.yield(event)
                        }
                    }
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    errBuffer.append(data)
                }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus != 0 {
                    let raw = errBuffer.snapshot()
                    let msg = String(data: raw, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? "yt-dlp exited with code \(proc.terminationStatus)"
                    continuation.yield(.failed(message: msg.isEmpty
                        ? "yt-dlp exited with code \(proc.terminationStatus)"
                        : msg))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.failed(message: error.localizedDescription))
                continuation.finish()
            }
        }
    }

    private static let progressRegex = try! NSRegularExpression(
        pattern: #"\[download\]\s+(\d+(?:\.\d+)?)%"#)

    private static func parseLine(_ line: String) -> DownloadEvent? {
        if line.hasPrefix("META ") {
            let json = String(line.dropFirst("META ".count))
            guard let data = json.data(using: .utf8) else { return nil }
            struct Meta: Decodable {
                let title: String?
                let duration: Double?
                let thumbnail: String?
            }
            guard let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return nil }
            return .metadata(
                title: meta.title ?? "Untitled",
                durationSeconds: meta.duration,
                thumbnailURL: meta.thumbnail.flatMap { URL(string: $0) }
            )
        }
        if line.hasPrefix("DONE ") {
            return .finished(file: URL(fileURLWithPath: String(line.dropFirst("DONE ".count))))
        }
        if line.hasPrefix("[download]") {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            if let match = progressRegex.firstMatch(in: line, range: range),
               match.numberOfRanges >= 2 {
                let pStr = nsLine.substring(with: match.range(at: 1))
                if let p = Double(pStr) {
                    return .progress(percent: p / 100.0)
                }
            }
        }
        return nil
    }
}

// MARK: - helpers

/// Thread-safe line buffering for streamed stdout.
private final class LineBuffer {
    private var leftover = ""
    private let lock = NSLock()

    func feed(_ chunk: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let combined = leftover + chunk
        let parts = combined.components(separatedBy: "\n")
        leftover = parts.last ?? ""
        return Array(parts.dropLast())
    }
}

/// Thread-safe Data accumulator for stderr.
private final class LockedData {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
