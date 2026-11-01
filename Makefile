APP_NAME   := Clawd Bar
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
RELEASE    := .build/release
INSTALL_TO := /Applications

.PHONY: all test build app icon install uninstall run clean

all: app

test:
	swift test

build:
	swift build -c release

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(RELEASE)/ClawdBar" "$(RELEASE)/clawd-hook" "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - "$(APP)/Contents/MacOS/clawd-hook"
	codesign --force --sign - "$(APP)"
	@echo "Built $(APP)"

# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	rm -rf "$(BUILD_DIR)/AppIcon.iconset"
	swift scripts/make-icon.swift "$(BUILD_DIR)/AppIcon.iconset" docs/images/icon.png
	iconutil -c icns "$(BUILD_DIR)/AppIcon.iconset" -o Resources/AppIcon.icns

install: app
	-pkill -x ClawdBar
	@while pgrep -x ClawdBar >/dev/null; do sleep 0.2; done
	rm -rf "$(INSTALL_TO)/$(APP_NAME).app"
	cp -R "$(APP)" "$(INSTALL_TO)/"
	open "$(INSTALL_TO)/$(APP_NAME).app"

uninstall:
	-pkill -x ClawdBar
	@while pgrep -x ClawdBar >/dev/null; do sleep 0.2; done
	rm -rf "$(INSTALL_TO)/$(APP_NAME).app"
	@echo "Removed the app. Use 'Remove Claude Code Hooks' before uninstalling, or delete the clawd-hook entries from ~/.claude/settings.json."

run: app
	open "$(APP)"

clean:
	rm -rf .build "$(BUILD_DIR)"
