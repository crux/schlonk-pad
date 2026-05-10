import Foundation
import SwiftUI

@MainActor
final class DownloadStore: ObservableObject {

    enum Phase: Equatable {
        case idle
        case fetching                                          // submitted, before metadata arrives
        case downloading(Metadata, percent: Double)
        case done(Metadata, file: URL, sizeBytes: Int64)
        case failed(message: String)
    }

    struct Metadata: Equatable {
        let title: String
        let durationSeconds: Double?
        let thumbnailURL: URL?
    }

    @Published var phase: Phase = .idle

    private let runner: EngineRunner
    private let outputDir: URL
    private var currentTask: Task<Void, Never>?

    init() {
        do {
            self.runner = try EngineRunner()
        } catch {
            fatalError("yt-dlp_macos missing from app bundle: \(error)")
        }
        self.outputDir = Self.makeOutputDir()
    }

    private static func makeOutputDir() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dir = downloads.appendingPathComponent("schlonk-pad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func submit(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        cancel()
        phase = .fetching

        let runner = self.runner
        let outputDir = self.outputDir
        currentTask = Task { [weak self] in
            var pendingMeta: Metadata?
            for await event in runner.download(urlString: trimmed, outputDir: outputDir) {
                if Task.isCancelled { return }
                guard let self else { return }
                switch event {
                case .metadata(let title, let duration, let thumb):
                    let meta = Metadata(title: title, durationSeconds: duration, thumbnailURL: thumb)
                    pendingMeta = meta
                    self.phase = .downloading(meta, percent: 0)
                case .progress(let p):
                    let meta = pendingMeta
                        ?? Metadata(title: "Downloading…", durationSeconds: nil, thumbnailURL: nil)
                    self.phase = .downloading(meta, percent: p)
                case .finished(let file):
                    let size = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int64) ?? 0
                    let meta = pendingMeta
                        ?? Metadata(title: file.lastPathComponent, durationSeconds: nil, thumbnailURL: nil)
                    self.phase = .done(meta, file: file, sizeBytes: size)
                case .failed(let msg):
                    self.phase = .failed(message: msg)
                }
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    func reset() {
        cancel()
        phase = .idle
    }
}
