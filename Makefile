PROJECT   = app/SchlonkPad.xcodeproj
SCHEME    = SchlonkPad
BUILD_DIR = build
APP_NAME  = SchlonkPad
DEPS_DIR  = deps
YTDLP     = $(DEPS_DIR)/yt-dlp_macos

# CONFIGURATION_BUILD_DIR needs an absolute path; build/ is symlinked to ~/.nosync.
BUILD_REAL = $(shell realpath "$(BUILD_DIR)")

DEV_VERSION = $(shell date +%Y.%m.%d).0

.PHONY: build release dist dist-dev run clean deps update-deps tag

deps: $(YTDLP)

$(YTDLP):
	scripts/fetch-yt-dlp.sh

update-deps:
	rm -f $(YTDLP)
	$(MAKE) deps

build: deps
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		CONFIGURATION_BUILD_DIR="$(BUILD_REAL)" build

release: deps
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

# tag creates a local annotated tag only — push manually when ready.
tag:
	@test -n "$(VERSION)" || (echo "usage: make tag VERSION=vX.Y.Z"; exit 1)
	@git diff --quiet && git diff --cached --quiet || (echo "working tree not clean"; exit 1)
	git tag -a $(VERSION) -m "$(VERSION)"
