import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: DownloadStore
    @State private var url: String = ""

    var body: some View {
        VStack(spacing: 16) {
            urlBar
            phaseContent
            Spacer(minLength: 0)
        }
        .padding()
        .dropDestination(for: URL.self) { items, _ in
            guard let dropped = items.first else { return false }
            url = dropped.absoluteString
            store.submit(urlString: dropped.absoluteString)
            return true
        }
    }

    // MARK: - URL bar

    @ViewBuilder
    private var urlBar: some View {
        HStack(spacing: 8) {
            TextField("Paste URL or drop here", text: $url)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .disabled(isBusy)
            Button(action: submit) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
        }
    }

    // MARK: - Phase

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .idle:
            EmptyView()
        case .fetching:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: 0).progressViewStyle(.linear)
                Text("Fetching…").font(.caption).foregroundColor(.secondary)
            }
        case .downloading(let meta, let percent):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: percent).progressViewStyle(.linear)
                if !meta.title.isEmpty {
                    Text(meta.title).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
        case .done(let meta, let file, let size):
            VStack(spacing: 12) {
                resultRow(meta: meta, file: file, size: size)
                shareRow(file: file)
            }
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundColor(.red)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Result row

    private func resultRow(meta: DownloadStore.Metadata, file: URL, size: Int64) -> some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail(meta: meta, file: file)
                .frame(width: 96, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                Text(meta.title).font(.callout).lineLimit(2)
                Text(metaLine(duration: meta.durationSeconds, size: size))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func thumbnail(meta: DownloadStore.Metadata, file: URL) -> some View {
        Group {
            if let thumbURL = meta.thumbnailURL {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(Color.gray.opacity(0.15))
                            .overlay(ProgressView().controlSize(.small))
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle().fill(Color.gray.opacity(0.15))
                            .overlay(Image(systemName: "film").foregroundColor(.secondary))
                    @unknown default:
                        Rectangle().fill(Color.gray.opacity(0.15))
                    }
                }
            } else {
                Rectangle().fill(Color.gray.opacity(0.15))
                    .overlay(Image(systemName: "film").font(.title2).foregroundColor(.secondary))
            }
        }
        .contentShape(Rectangle())
        .onDrag {
            // NSItemProvider(contentsOf:) registers a file representation that
            // browsers and Finder treat as a file drag (not just a URL string).
            NSItemProvider(contentsOf: file) ?? NSItemProvider()
        }
    }

    // MARK: - Share row

    @ViewBuilder
    private func shareRow(file _: URL) -> some View {
        HStack(spacing: 8) {
            Text("Post to:").font(.caption).foregroundColor(.secondary)
            shareButton("Bsky", url: "https://bsky.app/")
            shareButton("X", url: "https://x.com/compose/post")
            shareButton("TikTok", url: "https://www.tiktok.com/upload")
            shareButton("LinkedIn", url: "https://www.linkedin.com/feed/?shareActive=true")
            shareButton("FB", url: "https://www.facebook.com/")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shareButton(_ label: String, url: String) -> some View {
        Button(label) {
            if let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Helpers

    private var isBusy: Bool {
        switch store.phase {
        case .fetching, .downloading: return true
        default: return false
        }
    }

    private func submit() {
        store.submit(urlString: url)
    }

    private func metaLine(duration: Double?, size: Int64) -> String {
        var parts: [String] = []
        if let d = duration {
            parts.append(formatDuration(d))
        }
        if size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
