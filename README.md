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
    make build-release          # release-config build, no packaging
    make dist VERSION=x.y.z     # release build + DMG (local validation before tagging)
    make clean
    make icon                   # re-render iconset from assets/icon-1024.png

`build/` and `.git/` are symlinked to `~/.nosync/projects/schlonk-pad/` to keep
build artifacts and git internals off cloud-synced filesystems.

## Releases

Two channels:

| Channel | Tagged version | Trigger | Cask |
|---|---|---|---|
| Stable | `vX.Y.Z` (suggested: `v0.YYYYMMDD.N`) | push of a `v*` tag | `Casks/schlonk-pad.rb` |
| Dev | `YYYY.MM.DD.runNumber` (auto) | every push to `main` | `Casks/schlonk-pad-dev.rb` |

Make targets that drive them:

    make release-dev                    # push main → dev release
    make release VERSION=v0.20260510.0  # tag + push tag → stable release
    make tag VERSION=v0.20260510.0      # local tag only, no push

CI (in `.github/workflows/{release,release-dev}.yml`) builds the .app, patches
`CFBundleShortVersionString` to the version string and `CFBundleVersion` to the
GitHub Actions `run_number`, packages a DMG, attaches it to a GitHub release,
and pushes a fresh cask file into the [`crux/homebrew-tap`](https://github.com/crux/homebrew-tap)
repo. Users get the new build via `brew upgrade --cask schlonk-pad[-dev]`.

## Known limitations

- **ffmpeg not bundled yet** — sites that need post-processing (YouTube videos requiring separate video+audio stream merging, etc.) may produce lower quality or fail. Follow-up.
- **App Sandbox disabled** — schlonk-pad has full file system + network access. Trade-off for skipping the Mac App Store sandbox dance.
- **Re-share is open-composer + manual drag** — web composers don't accept media via URL parameters, so the flow is "open the compose URL in your browser, drag the file from schlonk-pad into it."

## License

MIT.
