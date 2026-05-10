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

    // MARK: - Phase content

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .idle:
            EmptyView()
        case .fetching:
            VStack(alignment: .leading, spacing: 6) {
                // Indeterminate linear bar — animated stripes signal "alive,
                // duration unknown." Switches to determinate as soon as the
                // first progress line arrives.
                ProgressView().progressViewStyle(.linear)
                Text("Fetching…").font(.caption).foregroundColor(.secondary)
            }
        case .downloading(let meta, let percent):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: percent).progressViewStyle(.linear)
                infoBlock(meta: meta, size: nil, file: nil)
            }
        case .done(let meta, let file, let size):
            VStack(alignment: .leading, spacing: 12) {
                infoBlock(meta: meta, size: size, file: file)
                thumbnail(meta: meta, file: file)
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

    // MARK: - Info block (title, duration, size, reveal)

    private func infoBlock(meta: DownloadStore.Metadata, size: Int64?, file: URL?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.title)
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let line = metaLine(duration: meta.durationSeconds, size: size)
                if !line.isEmpty {
                    Text(line).font(.caption).foregroundColor(.secondary)
                }
            }
            if let file = file {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                } label: {
                    Image(systemName: "folder")
                        .imageScale(.medium)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
        }
    }

    // MARK: - Thumbnail (full-width, draggable file source)

    private func thumbnail(meta: DownloadStore.Metadata, file: URL) -> some View {
        ZStack {
            Color.black.opacity(0.05)

            AsyncImage(url: meta.thumbnailURL) { phase in
                switch phase {
                case .empty:
                    ProgressView().controlSize(.small)
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    Image(systemName: "film")
                        .font(.title)
                        .foregroundColor(.secondary)
                @unknown default:
                    EmptyView()
                }
            }
        }
        // Lock the container to 16:9 so layout is predictable; vertical videos
        // get pillarboxed (centered with empty space on the sides) rather than
        // cropped.
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onDrag {
            let provider = NSItemProvider(contentsOf: file) ?? NSItemProvider()
            // suggestedName drives the filename at the drop destination. macOS
            // only forbids '/' in filenames; we replace it with '-' and trim
            // whitespace. Extension is supplied by the registered type id.
            let cleaned = meta.title
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                provider.suggestedName = cleaned
            }
            return provider
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

    private func metaLine(duration: Double?, size: Int64?) -> String {
        var parts: [String] = []
        if let d = duration {
            parts.append(formatDuration(d))
        }
        if let s = size, s > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: s, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
