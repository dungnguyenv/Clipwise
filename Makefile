# Clipwise build helpers.
# Requires full Xcode (not just Command Line Tools) and xcodegen.

PROJECT      := Clipwise.xcodeproj
SCHEME       := Clipwise
DERIVED_DATA := build
# Read the version from project.yml: xcodegen regenerates Clipwise/Info.plist
# from that file on every `generate` and always writes its default "1.0" there,
# while the built app reports MARKETING_VERSION. Accept only a dotted-numeric
# version: this value is interpolated into the hdiutil command line in `dmg`,
# so a crafted string would otherwise be run as shell. Anything unparseable
# falls back to 1.0.0.
VERSION      := $(shell grep -m1 -E '^[[:space:]]*MARKETING_VERSION:' project.yml | tr -d '" ' | cut -d: -f2 | grep -m1 -Ex '[0-9]+(\.[0-9]+)*' || echo 1.0.0)

# Ad-hoc signing keeps local builds working without an Apple Developer team.
SIGN_FLAGS := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=

DEBUG_APP   := $(DERIVED_DATA)/Build/Products/Debug/Clipwise.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Clipwise.app

.PHONY: doctor generate build release test run dmg clean

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

## Run the unit test bundle
test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
		-derivedDataPath $(DERIVED_DATA) $(SIGN_FLAGS) test

## Build and launch. Never use Xcode's Run button when testing paste —
## it re-signs the binary and macOS revokes the Accessibility grant.
run: build
	@pkill -x Clipwise || true
	open $(DEBUG_APP)

## Package the Release build as a DMG
dmg: release
	@rm -rf $(DERIVED_DATA)/dmg && mkdir -p $(DERIVED_DATA)/dmg release
	cp -R $(RELEASE_APP) $(DERIVED_DATA)/dmg/
	ln -s /Applications $(DERIVED_DATA)/dmg/Applications
	hdiutil create -volname "Clipwise" -srcfolder $(DERIVED_DATA)/dmg -ov -format UDZO \
		"release/Clipwise-$(VERSION).dmg"

clean:
	rm -rf $(DERIVED_DATA)
