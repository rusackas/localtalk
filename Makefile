APP_NAME = LocalTalk
BUILD_DIR = .build/release
BUNDLE_DIR = build/$(APP_NAME).app
DMG_NAME = $(APP_NAME).dmg
DMG_VOL = $(APP_NAME)
DMG_TMP = /tmp/lt-tmp.dmg
DMG_STAGING = /tmp/lt-staging
ENTITLEMENTS = Resources/LocalTalk.entitlements
# Source the framework's Versions/B directory directly. There are no symlinks
# inside Versions/B, so plain cp -R reproduces it byte-perfectly across any
# environment. We re-create the framework's top-level symlinks ourselves
# (Headers/Modules/Sparkle/etc. → Versions/Current/…) because SwiftPM's
# xcframework extraction on the macos-15 GitHub Actions runner replaces them
# with deep file copies, which Apple's notary rejects as "ambiguous bundle
# format" even though local codesign accepts the result.
SPARKLE_VERSION_B = .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B

# Set SIGNING_IDENTITY to a Developer ID for release builds (triggers hardened
# runtime + timestamp + entitlements). Defaults to ad-hoc signing for local dev.
SIGNING_IDENTITY ?= -
ifeq ($(SIGNING_IDENTITY),-)
CODESIGN_FLAGS = --force --sign - --identifier com.localtalk.app
SPARKLE_SIGN_FLAGS = --force --sign -
else
CODESIGN_FLAGS = --force --sign "$(SIGNING_IDENTITY)" --identifier com.localtalk.app \
                 --options runtime --entitlements $(ENTITLEMENTS) --timestamp
# Sparkle's helpers must be re-signed with our identity (hardened runtime +
# secure timestamp) so the parent app's signature stays valid. They keep their
# own bundle identifiers (set by Sparkle), so no --identifier override here.
SPARKLE_SIGN_FLAGS = --force --sign "$(SIGNING_IDENTITY)" \
                     --options runtime --timestamp
endif

.PHONY: build bundle icon dmg clean run

build:
	swift build -c release

icon:
	swift Scripts/make_icon.swift

bundle: icon build
	mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	mkdir -p $(BUNDLE_DIR)/Contents/Resources
	mkdir -p $(BUNDLE_DIR)/Contents/Frameworks
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE_DIR)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$(cat VERSION)" $(BUNDLE_DIR)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$(cat VERSION)" $(BUNDLE_DIR)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE_DIR)/Contents/Resources/AppIcon.icns
	# Reconstruct Sparkle.framework from Versions/B. See SPARKLE_VERSION_B
	# comment above for why we don't trust ditto here.
	rm -rf "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework"
	mkdir -p "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Versions"
	cp -R "$(SPARKLE_VERSION_B)" "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Versions/B"
	ln -s B "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Versions/Current"
	ln -s Versions/Current/Sparkle "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Sparkle"
	ln -s Versions/Current/Autoupdate "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Autoupdate"
	ln -s Versions/Current/Updater.app "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Updater.app"
	ln -s Versions/Current/Headers "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Headers"
	ln -s Versions/Current/Modules "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Modules"
	ln -s Versions/Current/PrivateHeaders "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/PrivateHeaders"
	ln -s Versions/Current/Resources "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Resources"
	ln -s Versions/Current/XPCServices "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/XPCServices"
	@echo "Sparkle.framework structure (should show symlinks at top level):"
	@ls -la "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/" | head -12
	codesign $(SPARKLE_SIGN_FLAGS) "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
	codesign $(SPARKLE_SIGN_FLAGS) "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
	codesign $(SPARKLE_SIGN_FLAGS) "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
	codesign $(SPARKLE_SIGN_FLAGS) "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
	codesign $(SPARKLE_SIGN_FLAGS) "$(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework"
	# SwiftPM synthesizes a Bundle.module accessor that looks at
	# Bundle.main.bundleURL.appendingPathComponent("<name>.bundle"), which for a .app
	# resolves to LocalTalk.app/<name>.bundle — but codesign rejects anything at the bundle
	# root. Ship the resource bundle at Contents/Resources/Hub.bundle and binary-patch
	# the hardcoded string in the compiled executable. Both "swift-transformers_Hub.bundle"
	# and "Contents/Resources/Hub.bundle" are 29 bytes, so in-place replacement is safe.
	# Codesign runs AFTER the patch so the signature covers the modified bytes.
	rm -rf $(BUNDLE_DIR)/Contents/Resources/Hub.bundle
	cp -R $(BUILD_DIR)/swift-transformers_Hub.bundle $(BUNDLE_DIR)/Contents/Resources/Hub.bundle
	python3 -c 'import sys; p="$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)"; d=open(p,"rb").read(); n=d.count(b"swift-transformers_Hub.bundle\0"); assert n>=1, "expected bundle path string in binary"; d=d.replace(b"swift-transformers_Hub.bundle\0", b"Contents/Resources/Hub.bundle\0"); open(p,"wb").write(d); print(f"patched {n} occurrence(s)")'
	codesign $(CODESIGN_FLAGS) $(BUNDLE_DIR)

dmg: bundle
	# Clean up any leftovers from a previous run
	rm -rf "$(DMG_STAGING)" "$(DMG_TMP)" "$(DMG_NAME)"
	hdiutil detach "/Volumes/$(DMG_VOL)" 2>/dev/null; true
	# Staging folder: app + /Applications alias
	mkdir -p "$(DMG_STAGING)"
	cp -r "$(BUNDLE_DIR)" "$(DMG_STAGING)/$(APP_NAME).app"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	# Create writable disk image from staging
	hdiutil create -srcfolder "$(DMG_STAGING)" -volname "$(DMG_VOL)" \
		-fs HFS+ -format UDRW -o "$(DMG_TMP)"
	# Mount and arrange icons
	hdiutil attach "$(DMG_TMP)" -mountpoint "/Volumes/$(DMG_VOL)" -noautoopen
	sleep 2
	bash Scripts/arrange_dmg.sh "$(DMG_VOL)" "$(APP_NAME).app" || true
	hdiutil detach "/Volumes/$(DMG_VOL)"
	# Convert to compressed read-only DMG
	hdiutil convert "$(DMG_TMP)" -format UDZO -imagekey zlib-level=9 -o "$(DMG_NAME)"
	# Clean up
	rm -rf "$(DMG_STAGING)" "$(DMG_TMP)"
	@echo "✓ $(DMG_NAME)"

clean:
	rm -rf .build build "$(DMG_NAME)"

run: bundle
	open $(BUNDLE_DIR)
