PROJECT := Reminder.xcodeproj
SCHEME := Reminder
DERIVED_DATA := build
DEBUG_APP := $(DERIVED_DATA)/Build/Products/Debug/Reminder.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Reminder.app
INSTALL_DIR := /Applications

.PHONY: generate build test run install clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED_DATA) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) test

run: build
	-pkill -x Reminder
	open $(DEBUG_APP)

# /Applications に置いたアプリだけがログイン時の自動起動に登録される
install: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED_DATA) build
	-pkill -x Reminder
	rm -rf $(INSTALL_DIR)/Reminder.app
	cp -R $(RELEASE_APP) $(INSTALL_DIR)/
	open $(INSTALL_DIR)/Reminder.app

clean:
	rm -rf $(DERIVED_DATA) $(PROJECT)
