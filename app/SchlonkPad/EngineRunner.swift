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
/// Known limitation: the PyInstaller-frozen yt-dlp_macos block-buffers stdout
/// when not on a TTY, and PYTHONUNBUFFERED is not honored by the frozen
/// interpreter. This means METADATA / PROGRESS / DONE events tend to arrive
/// in a burst at process exit rather than streaming in. The fix is a real
/// pseudo-terminal via openpty() — punted to a follow-up because the previous
/// `script(1)` wrapper attempt hangs without a controlling TTY.
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
                "--no-quiet",        // keep [download] progress alongside --print
                "--no-playlist",
                "--no-mtime",
                "-o", outputTemplate,
                "--print", "before_dl:META %(.{title,duration,thumbnail})j",
                "--print", "after_move:DONE %(filepath)s",
                urlString,
            ]

            // Best-effort hint to flush sooner. Frozen Python may ignore it.
            var env = ProcessInfo.processInfo.environment
            env["PYTHONUNBUFFERED"] = "1"
            env["PYTHONIOENCODING"] = "utf-8"
            process.environment = env

            // No stdin — prevents any blocking read by the child.
            process.standardInput = FileHandle.nullDevice

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let outLines = LineBuffer()
            let errBuffer = LockedData()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in outLines.feed(chunk) {
                    if let event = Self.parseLine(line) {
                        continuation.yield(event)
                    }
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    errBuffer.append(data)
                    // yt-dlp's [download] progress lines go to stderr; parse them too.
                    if let chunk = String(data: data, encoding: .utf8) {
                        for line in outLines.feed(chunk) {
                            if let event = Self.parseLine(line) {
                                continuation.yield(event)
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus != 0 {
                    let raw = errBuffer.snapshot()
                    let msg = String(data: raw, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? ""
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
        let normalized = combined.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n")
        leftover = parts.last ?? ""
        return Array(parts.dropLast())
    }
}

private final class LockedData {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}
