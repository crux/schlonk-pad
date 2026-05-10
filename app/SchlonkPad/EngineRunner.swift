import Foundation

enum DownloadEvent {
    case metadata(title: String, durationSeconds: Double?, thumbnailURL: URL?)
    case progress(percent: Double)
    case finished(file: URL)
    case failed(message: String)
}

/// Wraps the bundled yt-dlp_macos binary as a subprocess and surfaces lifecycle
/// events via an AsyncStream.
///
/// Implementation notes:
/// - We run yt-dlp under `/usr/bin/script -q /dev/null` so it sees a TTY on
///   stdout. Without that, the PyInstaller-frozen Python block-buffers stdout
///   (PYTHONUNBUFFERED isn't honored) and the app would only see output at exit.
/// - `--print` implies `--quiet`, which suppresses the usual `[download]` lines
///   we parse for progress, so we add `--no-quiet`.
/// - With the PTY, stderr is merged into the same stream as stdout — we read
///   both via a single pipe, strip ANSI escape codes, then pattern-match.
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
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")

            let outputTemplate = outputDir
                .appendingPathComponent("%(title).200B [%(id)s].%(ext)s")
                .path
            let ytdlpArgs = [
                "--newline",
                "--no-warnings",
                "--no-quiet",
                "--no-playlist",
                "--no-mtime",
                "-o", outputTemplate,
                "--print", "before_dl:META %(.{title,duration,thumbnail})j",
                "--print", "after_move:DONE %(filepath)s",
                urlString,
            ]
            // script -q /dev/null <yt-dlp> <args...>
            process.arguments = ["-q", "/dev/null", executable.path] + ytdlpArgs

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe  // merged into the same stream by the PTY anyway

            let lineBuffer = LineBuffer()
            let recentLines = RingBuffer(capacity: 200)

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in lineBuffer.feed(chunk) {
                    recentLines.append(line)
                    if let event = Self.parseLine(line) {
                        continuation.yield(event)
                    }
                }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus != 0 {
                    let tail = recentLines.tail(8).joined(separator: "\n")
                    let msg = tail.isEmpty
                        ? "yt-dlp exited with code \(proc.terminationStatus)"
                        : tail
                    continuation.yield(.failed(message: msg))
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
    private static let ansiRegex = try! NSRegularExpression(
        pattern: "\\x1B\\[[0-9;]*m")

    private static func parseLine(_ raw: String) -> DownloadEvent? {
        let nsRaw = raw as NSString
        let stripped = ansiRegex.stringByReplacingMatches(
            in: raw,
            range: NSRange(location: 0, length: nsRaw.length),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespaces)

        if stripped.hasPrefix("META ") {
            let json = String(stripped.dropFirst("META ".count))
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
        if stripped.hasPrefix("DONE ") {
            return .finished(file: URL(fileURLWithPath: String(stripped.dropFirst("DONE ".count))))
        }
        if stripped.hasPrefix("[download]") {
            let nsLine = stripped as NSString
            if let match = progressRegex.firstMatch(
                in: stripped,
                range: NSRange(location: 0, length: nsLine.length)
            ), match.numberOfRanges >= 2 {
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

private final class LineBuffer {
    private var leftover = ""
    private let lock = NSLock()

    func feed(_ chunk: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let combined = leftover + chunk
        // PTY uses \r\n by default; normalize then split on \n.
        let normalized = combined.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n")
        leftover = parts.last ?? ""
        return Array(parts.dropLast())
    }
}

private final class RingBuffer {
    private var lines: [String] = []
    private let capacity: Int
    private let lock = NSLock()

    init(capacity: Int) { self.capacity = capacity }

    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    func tail(_ n: Int) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(lines.suffix(n))
    }
}
