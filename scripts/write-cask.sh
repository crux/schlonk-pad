#!/bin/bash
# Usage: write-cask.sh VERSION SHA OUTPUT_FILE
set -e
VERSION=$1
SHA=$2
OUTPUT=$3

cat > "$OUTPUT" << CASK
cask "schlonk-pad" do
  version "${VERSION}"
  sha256 "${SHA}"
  url "https://github.com/crux/schlonk-pad/releases/download/v#{version}/SchlonkPad-#{version}.dmg"

  name "schlonk-pad"
  desc "macOS GUI for downloading videos from social media posts"
  homepage "https://github.com/crux/schlonk-pad"

  app "SchlonkPad.app"

  postflight do
    system_command "/usr/bin/xattr",
      args: ["-rd", "com.apple.quarantine", "#{appdir}/SchlonkPad.app"]
  end
end
CASK
