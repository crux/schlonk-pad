PROJECT   = app/SchlonkPad.xcodeproj
SCHEME    = SchlonkPad
BUILD_DIR = build
APP_NAME  = SchlonkPad
DEPS_DIR  = deps
YTDLP     = $(DEPS_DIR)/yt-dlp_macos
ICON_1024 = assets/icon-1024.png
ICONSET   = app/SchlonkPad/Assets.xcassets/AppIcon.appiconset

# CONFIGURATION_BUILD_DIR needs an absolute path; build/ is symlinked to ~/.nosync.
BUILD_REAL = $(shell realpath "$(BUILD_DIR)")

DEV_VERSION = $(shell date +%Y.%m.%d).0

.PHONY: build build-release dist dist-dev run clean deps update-deps tag icon release release-dev

deps: $(YTDLP)

$(YTDLP):
	scripts/fetch-yt-dlp.sh

update-deps:
	rm -f $(YTDLP)
	$(MAKE) deps

build: deps
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		CONFIGURATION_BUILD_DIR="$(BUILD_REAL)" build

build-release: deps
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		CONFIGURATION_BUILD_DIR="$(BUILD_REAL)" build

dist: deps
ifndef VERSION
	$(error VERSION is required: make dist VERSION=0.1.0)
endif
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		CONFIGURATION_BUILD_DIR="$(BUILD_REAL)" build
	hdiutil create \
		-volname "schlonk-pad" \
		-srcfolder "$(BUILD_REAL)/$(APP_NAME).app" \
		-ov -format UDZO \
		"$(BUILD_REAL)/$(APP_NAME)-$(VERSION).dmg"
	@echo "Built: $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg"
	@shasum -a 256 "$(BUILD_REAL)/$(APP_NAME)-$(VERSION).dmg"

dist-dev: deps
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		PRODUCT_BUNDLE_IDENTIFIER="com.crux.schlonk-pad.dev" \
		CONFIGURATION_BUILD_DIR="$(BUILD_REAL)" build
	/usr/libexec/PlistBuddy -c \
		"Set :CFBundleDisplayName 'schlonk-pad (dev)'" \
		"$(BUILD_REAL)/$(APP_NAME).app/Contents/Info.plist"
	mv "$(BUILD_REAL)/$(APP_NAME).app" "$(BUILD_REAL)/$(APP_NAME) Dev.app"
	hdiutil create \
		-volname "schlonk-pad (dev)" \
		-srcfolder "$(BUILD_REAL)/$(APP_NAME) Dev.app" \
		-ov -format UDZO \
		"$(BUILD_REAL)/$(APP_NAME)-dev-$(DEV_VERSION).dmg"
	@echo "Built: $(BUILD_DIR)/$(APP_NAME)-dev-$(DEV_VERSION).dmg"
	@shasum -a 256 "$(BUILD_REAL)/$(APP_NAME)-dev-$(DEV_VERSION).dmg"

run: build
	-pkill -x "$(APP_NAME)" 2>/dev/null; sleep 0.3
	open "$(BUILD_DIR)/$(APP_NAME).app"

clean:
	rm -rf "$(BUILD_DIR)"/*

# Regenerate the iconset entries from assets/icon-1024.png. Replace that PNG
# with a new 1024×1024 (transparent corners preferred) and run `make icon`.
icon:
	@test -f $(ICON_1024) || (echo "missing $(ICON_1024)"; exit 1)
	@for entry in "16x16:16" "16x16@2x:32" "32x32:32" "32x32@2x:64" \
		"128x128:128" "128x128@2x:256" "256x256:256" "256x256@2x:512" \
		"512x512:512" "512x512@2x:1024"; do \
		name=$${entry%:*}; px=$${entry#*:}; \
		magick $(ICON_1024) -resize $${px}x$${px} $(ICONSET)/icon_$${name}.png; \
	done
	@echo "Regenerated $(ICONSET)/icon_*.png from $(ICON_1024)"

# --- release orchestration ---------------------------------------------------
# Stable release:  make release VERSION=v0.YYYYMMDD.N
#   1. verifies working tree is clean
#   2. creates an annotated tag locally
#   3. pushes the tag → triggers release.yml on the remote
#
# Dev release:     make release-dev
#   1. pushes the current main branch → triggers release-dev.yml on the remote

# tag creates a local annotated tag only (no push). Useful when you want to
# tag now and decide on the push later. Use `make release` for the full flow.
tag:
	@test -n "$(VERSION)" || (echo "usage: make tag VERSION=vX.Y.Z"; exit 1)
	@git diff --quiet && git diff --cached --quiet || (echo "working tree not clean"; exit 1)
	git tag -a $(VERSION) -m "$(VERSION)"

release:
	@test -n "$(VERSION)" || (echo "usage: make release VERSION=vX.Y.Z (suggested: v0.YYYYMMDD.N)"; exit 1)
	@git diff --quiet && git diff --cached --quiet || (echo "working tree not clean"; exit 1)
	@if git rev-parse --verify "refs/tags/$(VERSION)" >/dev/null 2>&1; then \
		echo "tag $(VERSION) already exists locally; aborting"; exit 1; \
	fi
	git tag -a $(VERSION) -m "$(VERSION)"
	git push origin $(VERSION)
	@echo "→ pushed $(VERSION); release.yml is firing on github.com/crux/schlonk-pad/actions"

release-dev:
	git push origin main
	@echo "→ pushed main; release-dev.yml is firing on github.com/crux/schlonk-pad/actions"
