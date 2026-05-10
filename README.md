# schlonk-pad

macOS GUI for grabbing videos from social media posts. Native Swift app wrapping the download, and option to fast start upload to other sites. 

**Status:** early scaffold. Not buildable yet.

## Plan

- Native AppKit/SwiftUI window, macOS 13+, universal binary (Apple Silicon + Intel).
- Bundles yt-dlp (and eventually ffmpeg) inside the `.app`.
- Single-shot UX: paste a URL → download → drag the result anywhere.
- "Post to <blusky>" buttons open the platform's web composer; the app morphs into a small floating panel keeping the file as a drag source so you can drop it into the open compose dialog.
- Distributed via Homebrew Cask (not notarized — cask handles Gatekeeper).

## Local development

Prerequisites: macOS 13+, Xcode.

    make deps         # fetch yt-dlp into deps/
    make build        # debug build (once Xcode project exists)
    make run          # build + launch
    make clean        # remove build artifacts

## License

MIT.
