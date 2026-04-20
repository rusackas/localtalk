APP_NAME = LocalTalk
BUILD_DIR = .build/release
BUNDLE_DIR = build/$(APP_NAME).app
DMG_NAME = $(APP_NAME).dmg
DMG_VOL = $(APP_NAME)
DMG_TMP = /tmp/lt-tmp.dmg
DMG_STAGING = /tmp/lt-staging

.PHONY: build bundle icon dmg clean run

build:
	swift build -c release

icon:
	swift Scripts/make_icon.swift

bundle: icon build
	mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	mkdir -p $(BUNDLE_DIR)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE_DIR)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE_DIR)/Contents/Resources/AppIcon.icns
	# SwiftPM resource bundles (e.g. swift-transformers_Hub.bundle with fallback tokenizer configs).
	# Without these, Bundle.module fatalErrors whenever WhisperKit hits its fallback path.
	find -L $(BUILD_DIR) -maxdepth 1 -name '*.bundle' -exec cp -R {} $(BUNDLE_DIR)/Contents/Resources/ \;
	codesign --force --sign - --identifier com.localtalk.app $(BUNDLE_DIR)

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
