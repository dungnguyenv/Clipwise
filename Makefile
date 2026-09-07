# Clipwise build helpers.
# Requires full Xcode (not just Command Line Tools) and xcodegen.

PROJECT      := Clipwise.xcodeproj
SCHEME       := Clipwise
DERIVED_DATA := build
VERSION      := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Clipwise/Info.plist 2>/dev/null || echo 1.0.0)

# Ad-hoc signing keeps local builds working without an Apple Developer team.
SIGN_FLAGS := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=

DEBUG_APP   := $(DERIVED_DATA)/Build/Products/Debug/Clipwise.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Clipwise.app

.PHONY: doctor generate build release run dmg clean

## Verify the toolchain is set up correctly
doctor:
	@printf 'xcodegen:   '; xcodegen --version 2>/dev/null || echo 'MISSING — brew install xcodegen'
	@printf 'xcode-select: %s\n' "$$(xcode-select -p)"
	@printf 'xcodebuild: '; xcodebuild -version 2>&1 | head -1
	@printf 'macOS SDK:  '; xcodebuild -showsdks 2>/dev/null | grep -m1 macosx || echo 'none'

## Regenerate Clipwise.xcodeproj from project.yml
generate:
	xcodegen generate

## Debug build
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) $(SIGN_FLAGS) build

## Release build
release: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED_DATA) $(SIGN_FLAGS) build

## Build and launch. Never use Xcode's Run button when testing paste —
## it re-signs the binary and macOS revokes the Accessibility grant.
run: build
	@pkill -x Clipwise || true
	open $(DEBUG_APP)

## Package the Release build as a DMG
dmg: release
	@rm -rf $(DERIVED_DATA)/dmg && mkdir -p $(DERIVED_DATA)/dmg
	cp -R $(RELEASE_APP) $(DERIVED_DATA)/dmg/
	ln -s /Applications $(DERIVED_DATA)/dmg/Applications
	hdiutil create -volname "Clipwise" -srcfolder $(DERIVED_DATA)/dmg -ov -format UDZO \
		release/Clipwise-$(VERSION).dmg

clean:
	rm -rf $(DERIVED_DATA)
