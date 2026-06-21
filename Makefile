PROJECT := hisle.xcodeproj
SCHEME := hisle
CONFIGURATION ?= Debug
DESTINATION ?= generic/platform=macOS
BUILD_DIR ?= $(CURDIR)/build
PRODUCT_NAME ?= hisle
PACKAGE_DIR ?= $(BUILD_DIR)/dist
DMG_NAME ?=
DMG_VOLUME_NAME ?= hisle
DMG_SIGN_IDENTITY ?=
CODE_SIGN_STYLE ?=
CODE_SIGN_IDENTITY ?=
DEVELOPMENT_TEAM ?=
OTHER_CODE_SIGN_FLAGS ?=
NU := nix develop --command -- nu
ICON_NU := nix develop .\#icon-work --command -- nu
SWIFT := nix develop --ignore-environment --command -- swift
XCODEBUILD_ENV := env -u CC -u CXX -u LD -u SDKROOT -u NIX_CC -u NIX_CFLAGS_COMPILE -u NIX_CFLAGS_LINK -u NIX_LDFLAGS
XCODEBUILD := $(XCODEBUILD_ENV) /usr/bin/xcodebuild

.PHONY: all help build dmg install-debug uninstall clean icons check-toolchain core-spec-check gui-smoke-test

all: help

help:
	@echo 'Available commands:'
	@echo '    build         -- build the macOS input method app'
	@echo '    dmg           -- build and package a local DMG artifact'
	@echo '    install-debug -- build and install into ~/Library/Input Methods'
	@echo '    uninstall     -- remove the local debug install'
	@echo '    clean         -- remove local build products'
	@echo '    icons         -- render input method icon assets'
	@echo '    check-toolchain -- print active Xcode toolchain information'
	@echo '    core-spec-check -- validate the Cole Sebeol core contract'
	@echo '    gui-smoke-test -- run the Sublime Text GUI smoke test with hisle logs'

check-toolchain:
	$(XCODEBUILD) -version
	xcrun --find swiftc
	xcrun --sdk macosx --show-sdk-path

build:
	$(XCODEBUILD) \
		-project '$(PROJECT)' \
		-scheme '$(SCHEME)' \
		-configuration '$(CONFIGURATION)' \
		-destination '$(DESTINATION)' \
		SYMROOT='$(BUILD_DIR)' \
		build

dmg:
	PROJECT='$(PROJECT)' \
	SCHEME='$(SCHEME)' \
	CONFIGURATION='$(CONFIGURATION)' \
	DESTINATION='$(DESTINATION)' \
	BUILD_DIR='$(BUILD_DIR)' \
	PRODUCT_NAME='$(PRODUCT_NAME)' \
	PACKAGE_DIR='$(PACKAGE_DIR)' \
	DMG_NAME='$(DMG_NAME)' \
	DMG_VOLUME_NAME='$(DMG_VOLUME_NAME)' \
	DMG_SIGN_IDENTITY='$(DMG_SIGN_IDENTITY)' \
	CODE_SIGN_STYLE='$(CODE_SIGN_STYLE)' \
	CODE_SIGN_IDENTITY='$(CODE_SIGN_IDENTITY)' \
	DEVELOPMENT_TEAM='$(DEVELOPMENT_TEAM)' \
	OTHER_CODE_SIGN_FLAGS='$(OTHER_CODE_SIGN_FLAGS)' \
	$(NU) tools/package_dmg.nu

core-spec-check:
	$(SWIFT) run --quiet --package-path hisle-core hisle-core-spec-check

install-debug:
	PROJECT='$(PROJECT)' \
	SCHEME='$(SCHEME)' \
	CONFIGURATION='$(CONFIGURATION)' \
	DESTINATION='$(DESTINATION)' \
	BUILD_DIR='$(BUILD_DIR)' \
	$(NU) tools/install_debug.nu

gui-smoke-test: core-spec-check install-debug
	$(NU) tools/gui_smoke_test.nu

uninstall:
	$(NU) tools/uninstall.nu

icons:
	$(ICON_NU) tools/render_icons.nu

clean:
	rm -rf '$(BUILD_DIR)'
