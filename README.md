# schlonk-pad

macOS GUI for grabbing videos from social media posts. Native Swift app wrapping yt-dlp for the download, with a fast-start upload flow to other sites.

Sister project to [schlonk](https://github.com/crux/schlonk) (the CLI). They share the name, not the engine.

## Installation

Stable:

    brew install --cask crux/tap/schlonk-pad

Dev channel (latest builds from main, may be unstable):

    brew install --cask crux/tap/schlonk-pad-dev

Both versions co-install; dev installs as `SchlonkPad Dev.app`. Not notarized — the cask strips the Gatekeeper quarantine attribute on install, no manual right-click-and-Open dance required.

Upgrade: `brew upgrade --cask schlonk-pad`. Uninstall: `brew uninstall --cask schlonk-pad`.

## Use

Paste a URL into the field and press Enter, or drop a URL onto the window. When the download completes, drag the thumbnail anywhere to copy the file out, or click a "Post to" button to open the target platform's compose URL in your browser — keep the schlonk-pad window visible so you can drag the file into the open composer.

Files land in `~/Downloads/schlonk-pad/`.

## Local development

Prerequisites: macOS 13+, Xcode.

    make deps                   # fetch yt-dlp into deps/
    make build                  # debug build
    make run                    # build + launch
    make release                # release build, no packaging
    make dist VERSION=x.y.z     # release build + DMG (local validation before tagging)
    make clean

`bin/` and `.git/` are symlinked to `~/.nosync/projects/schlonk-pad/` to keep build artifacts and git internals off cloud-synced filesystems.

## Releases

Dev builds run on every push to main, versioned `YYYY.MM.DD.runNumber`.
Stable releases are triggered by pushing a `v*` tag (suggested form: `v0.YYYYMMDD.N`).

## Known limitations

- **ffmpeg not bundled yet** — sites that need post-processing (YouTube videos requiring separate video+audio stream merging, etc.) may produce lower quality or fail. Follow-up.
- **App Sandbox disabled** — schlonk-pad has full file system + network access. Trade-off for skipping the Mac App Store sandbox dance.
- **Re-share is open-composer + manual drag** — web composers don't accept media via URL parameters, so the flow is "open the compose URL in your browser, drag the file from schlonk-pad into it."

## License

MIT.
