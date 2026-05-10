import SwiftUI

struct ContentView: View {
    @State private var url: String = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                TextField("Paste URL or drop here", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
                Button(action: submit) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Placeholder for progress / result row / share buttons.
            // Wired up in subsequent commits.
            Spacer()
        }
        .padding()
    }

    private func submit() {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // TODO: invoke EngineRunner (yt-dlp subprocess)
        print("submit:", trimmed)
    }
}

#Preview {
    ContentView()
}
