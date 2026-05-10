import Foundation
import Darwin

enum DownloadEvent {
    case metadata(title: String, durationSeconds: Double?, thumbnailURL: URL?)
    case progress(percent: Double)
    case finished(file: URL)
    case failed(message: String)
}

/// Wraps the bundled yt-dlp_macos binary as a subprocess and surfaces lifecycle
/// events via an AsyncStream.
///
/// We attach the child's stdout/stderr to a pseudo-terminal slave (via openpty)
/// so the PyInstaller-frozen Python interpreter — which would otherwise
/// block-buffer stdout when piped — sees a TTY and uses line-buffered I/O.
/// Without this, every event would arrive in a single burst at process exit
/// and the progress bar would never move.
final class EngineRunner {

    enum Error: Swift.Error, LocalizedError {
        case binaryMissing
        case ptyFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .binaryMissing: return "yt-dlp_macos not found in app bundle"
            case .ptyFailed(let code): return "openpty() failed (errno \(code))"
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
            // Allocate a pseudo-terminal pair.
            var master: Int32 = -1
            var slave: Int32 = -1
            guard openpty(&master, &slave, nil, nil, nil) == 0 else {
                let err = errno
                continuation.yield(.failed(message: "openpty() failed: errno \(err)"))
                continuation.finish()
                return
            }

            let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: false)
            let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

            let process = Process()
            process.executableURL = executable

            let outputTemplate = outputDir
                .appendingPathComponent("%(title).200B [%(id)s].%(ext)s")
                .path
            process.arguments = [
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

            // PTY merges stderr into the same stream by virtue of both being
            // wired to the same slave fd.
            process.standardOutput = slaveHandle
            process.standardError = slaveHandle
            process.standardInput = FileHandle.nullDevice

            let outLines = LineBuffer()
            let recent = RingBuffer(capacity: 200)

            masterHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    // EOF on master — child closed its slave.
                    return
                }
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                for line in outLines.feed(chunk) {
                    recent.append(line)
                    if let event = Self.parseLine(line) {
                        continuation.yield(event)
                    }
                }
            }

            process.terminationHandler = { proc in
                masterHandle.readabilityHandler = nil
                close(master)
                if proc.terminationStatus != 0 {
                    let tail = recent.tail(8).joined(separator: "\n")
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
                // Once the child has its own copy of the slave (via posix_spawn
                // dup2), close the parent's copy so the master sees EOF when
                // the child exits.
                close(slave)
            } catch {
                close(master)
                close(slave)
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
        // PTY emits \r\n line endings; normalize before split.
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
