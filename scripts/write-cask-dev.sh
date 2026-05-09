#!/bin/bash
# Usage: write-cask-dev.sh VERSION SHA OUTPUT_FILE
set -e
VERSION=$1
SHA=$2
OUTPUT=$3

cat > "$OUTPUT" << CASK
cask "schlonk-pad-dev" do
  version "${VERSION}"
  sha256 "${SHA}"
  url "https://github.com/crux/schlonk-pad/releases/download/dev/SchlonkPad-dev-#{version}.dmg"

  name "schlonk-pad (dev)"
  desc "macOS GUI for downloading videos from social media posts (dev channel)"
  homepage "https://github.com/crux/schlonk-pad"

  app "SchlonkPad Dev.app"

  postflight do
    system_command "/usr/bin/xattr",
      args: ["-rd", "com.apple.quarantine", "#{appdir}/SchlonkPad Dev.app"]
  end
end
CASK
