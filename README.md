# schlonk-pad

macOS GUI for grabbing videos from social media posts. Includes fast-start upload flow button for other sites, and video can be dragged into posts or any local filesystem location. Native Swift app wrapping yt-dlp for the download.

![demo](assets/demo.gif)

*A social-media post pasted into schlonk-pad, downloaded, then dragged into an MS Teams chat. The recipient gets the video file directly — no sign-up, no need to visit the source platform.*

Sister project to [schlonk](https://github.com/crux/schlonk) (the CLI). They share the name, not the engine.

## Installation

Stable:

    brew install --cask crux/tap/schlonk-pad

Dev channel (latest builds from main, may be unstable):

    brew install --cask crux/tap/schlonk-pad-dev

Both versions co-install; dev installs as `SchlonkPad Dev.app`. The cask strips the Gatekeeper quarantine attribute on install — no manual right-click-and-Open dance required, no Apple notarization in the path. (See [Why the warning?](#why-the-warning) below for the rationale.)

Upgrade: `brew upgrade --cask schlonk-pad`. Uninstall: `brew uninstall --cask schlonk-pad`.

## Manual install (no Homebrew)

Brew is the recommended path because it handles the quarantine strip and auto-updates. If you don't use Homebrew, the same DMGs are also published on the [GitHub releases page](https://github.com/crux/schlonk-pad/releases):

1. Download the latest `SchlonkPad-x.y.z.dmg` (stable) or `SchlonkPad-dev-yyyy.mm.dd.n.dmg` (dev).
2. Open the DMG, drag the app into `/Applications`.
3. First launch will be blocked by Gatekeeper — see below.

### Why the warning?

When you first launch a manually-installed copy, macOS shows
*"schlonk-pad can't be opened, the developer cannot be verified"*. That's
Apple's Gatekeeper. **This project deliberately doesn't go through Apple's
notarization flow** — notarization means submitting every build to Apple for
review-and-stapling before it can launch cleanly, which would put Apple in the
role of gatekeeper for an open-source tool that they don't need to be in.

Two ways past the dialog:

- **One-time bypass**: right-click the app in Finder → **Open** → confirm in the dialog. macOS remembers; subsequent launches just work.
- **Strip the quarantine attribute** (the same thing the Homebrew cask does automatically):

      xattr -rd com.apple.quarantine /Applications/SchlonkPad.app

The Homebrew cask runs that `xattr` line in its `postflight` hook on every install/upgrade, which is why brew users never see the warning. Manual install is fine if you'd rather skip the terminal route — you just do step 3 once per install.

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
