PROJECT := Reminder.xcodeproj
SCHEME := Reminder
APP_NAME := Reminder For ADHD
DERIVED_DATA := build
DEBUG_APP := $(DERIVED_DATA)/Build/Products/Debug/$(APP_NAME).app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: generate build test run install clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED_DATA) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) test

run: build
	-pkill -x "$(APP_NAME)"
	open "$(DEBUG_APP)"

# /Applications に置いたアプリだけがログイン時の自動起動に登録される
install: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED_DATA) build
	-pkill -x "$(APP_NAME)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(RELEASE_APP)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf $(DERIVED_DATA) $(PROJECT)
