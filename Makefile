APP_NAME = LocalTalk
BUILD_DIR = .build/release
BUNDLE_DIR = build/$(APP_NAME).app

.PHONY: build bundle clean run

build:
	swift build -c release

bundle: build
	mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	mkdir -p $(BUNDLE_DIR)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE_DIR)/Contents/Info.plist
	codesign --force --sign - --identifier com.localtalk.app $(BUNDLE_DIR)

clean:
	rm -rf .build build

run: bundle
	open $(BUNDLE_DIR)
