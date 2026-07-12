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
NU ?= nu
NPM ?= npm
SWIFT ?= swift
SWIFTLINT ?= swiftlint
BROWSER_OBSERVER_DIR ?= tools/chrome-ime
XCODEBUILD_ENV := env -u CC -u CXX -u LD -u SDKROOT -u NIX_CC -u NIX_CFLAGS_COMPILE -u NIX_CFLAGS_LINK -u NIX_LDFLAGS
XCODEBUILD := $(XCODEBUILD_ENV) /usr/bin/xcodebuild

.PHONY: all help require-nix-shell require-app-shell require-default-shell require-core-shell require-browser-shell require-icon-shell build dmg install-debug uninstall clean icons check-toolchain version-check swiftlint marked-range-policy-check browser-observer-check core-spec-check gui-smoke-test chrome-ime-repro firefox-ime-repro atlassian-confluence-login atlassian-confluence-repro

all: help

help:
	@echo 'Available commands, run from the owning Nix dev shell:'
	@echo '    nix develop --command -- make build'
	@echo '    nix develop --command -- make dmg'
	@echo '    nix develop --command -- make install-debug'
	@echo '    nix develop --command -- make uninstall'
	@echo '    nix develop --command -- make clean'
	@echo '    nix develop --command -- make check-toolchain'
	@echo '    nix develop --command -- make version-check'
	@echo '    nix develop --command -- make swiftlint'
	@echo '    nix develop --command -- make marked-range-policy-check'
	@echo '    nix develop .#browser --command -- make browser-observer-check'
	@echo '    nix develop --command -- make gui-smoke-test'
	@echo '    nix develop .#core --command -- make core-spec-check'
	@echo '    nix develop .#browser --command -- make chrome-ime-repro'
	@echo '    nix develop .#browser --command -- make firefox-ime-repro'
	@echo '    nix develop .#browser --command -- make atlassian-confluence-login'
	@echo '    nix develop .#browser --command -- make atlassian-confluence-repro'
	@echo '    nix develop .#icon --command -- make icons'

require-nix-shell:
	@if [ -z "$$IN_NIX_SHELL" ]; then \
		echo 'Run make from the owning Nix dev shell:' >&2; \
		echo '    nix develop --command -- make <target>' >&2; \
		echo '    nix develop .#core --command -- make core-spec-check' >&2; \
		echo '    nix develop .#browser --command -- make chrome-ime-repro' >&2; \
		echo '    nix develop .#browser --command -- make firefox-ime-repro' >&2; \
		echo '    nix develop .#browser --command -- make atlassian-confluence-repro' >&2; \
		echo '    nix develop .#icon --command -- make icons' >&2; \
		exit 1; \
	fi

require-app-shell: require-nix-shell
	@case "$$HISLE_DEV_SHELL" in \
		default|browser) ;; \
		*) echo 'Run this target from the app/browser Nix dev shell:' >&2; \
		   echo '    nix develop --command -- make <target>' >&2; \
		   echo '    nix develop .#browser --command -- make chrome-ime-repro' >&2; \
		   echo '    nix develop .#browser --command -- make firefox-ime-repro' >&2; \
		   echo '    nix develop .#browser --command -- make atlassian-confluence-repro' >&2; \
		   exit 1 ;; \
	esac

require-default-shell: require-nix-shell
	@if [ "$$HISLE_DEV_SHELL" != 'default' ]; then \
		echo 'Run this target from the default Nix dev shell:' >&2; \
		echo '    nix develop --command -- make <target>' >&2; \
		exit 1; \
	fi

require-core-shell: require-nix-shell
	@if [ "$$HISLE_DEV_SHELL" != 'core' ]; then \
		echo 'Run this target from the core Nix dev shell:' >&2; \
		echo '    nix develop .#core --command -- make core-spec-check' >&2; \
		exit 1; \
	fi

require-browser-shell: require-nix-shell
	@if [ "$$HISLE_DEV_SHELL" != 'browser' ]; then \
		echo 'Run this target from the browser Nix dev shell:' >&2; \
		echo '    nix develop .#browser --command -- make browser-observer-check' >&2; \
		echo '    nix develop .#browser --command -- make chrome-ime-repro' >&2; \
		echo '    nix develop .#browser --command -- make firefox-ime-repro' >&2; \
		echo '    nix develop .#browser --command -- make atlassian-confluence-repro' >&2; \
		exit 1; \
	fi

require-icon-shell: require-nix-shell
	@if [ "$$HISLE_DEV_SHELL" != 'icon' ]; then \
		echo 'Run this target from the icon Nix dev shell:' >&2; \
		echo '    nix develop .#icon --command -- make icons' >&2; \
		exit 1; \
	fi

check-toolchain: require-app-shell
	@echo "HISLE_DEV_SHELL=$${HISLE_DEV_SHELL:-<unset>}"
	$(XCODEBUILD) -version
	xcrun --find swiftc
	xcrun swiftc --version
	xcrun --sdk macosx --show-sdk-path
	@if command -v swiftc >/dev/null; then command -v swiftc; else echo 'swiftc not found on PATH'; fi

version-check: require-default-shell
	$(NU) tools/check_versions.nu

swiftlint: require-app-shell
	$(SWIFTLINT) lint

marked-range-policy-check: require-default-shell
	$(NU) tools/marked_text_range_policy_check.nu

browser-observer-check: require-browser-shell
	@if [ ! -f '$(BROWSER_OBSERVER_DIR)/node_modules/playwright-core/package.json' ]; then \
		echo 'Installing browser observer Node dependencies...'; \
		if [ -f '$(BROWSER_OBSERVER_DIR)/package-lock.json' ]; then \
			$(NPM) --prefix '$(BROWSER_OBSERVER_DIR)' ci --ignore-scripts --no-audit --no-fund; \
		else \
			$(NPM) --prefix '$(BROWSER_OBSERVER_DIR)' install --ignore-scripts --no-audit --no-fund; \
		fi; \
	fi
	$(NPM) --prefix '$(BROWSER_OBSERVER_DIR)' test

build: require-app-shell
	$(XCODEBUILD) \
		-project '$(PROJECT)' \
		-scheme '$(SCHEME)' \
		-configuration '$(CONFIGURATION)' \
		-destination '$(DESTINATION)' \
		SYMROOT='$(BUILD_DIR)' \
		build

dmg: require-app-shell
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

core-spec-check: require-core-shell
	$(SWIFT) run --quiet --package-path hisle-core hisle-core-spec-check

install-debug: require-app-shell
	PROJECT='$(PROJECT)' \
	SCHEME='$(SCHEME)' \
	CONFIGURATION='$(CONFIGURATION)' \
	DESTINATION='$(DESTINATION)' \
	BUILD_DIR='$(BUILD_DIR)' \
	$(NU) tools/install_debug.nu

gui-smoke-test: require-app-shell install-debug
	$(NU) tools/gui_smoke_test.nu

chrome-ime-repro: require-browser-shell install-debug
	$(NU) tools/chrome_ime_repro.nu

firefox-ime-repro: require-browser-shell install-debug
	$(NU) tools/firefox_ime_repro.nu

atlassian-confluence-login: require-browser-shell
	HISLE_ATLASSIAN_LOGIN_ONLY=1 $(NU) tools/atlassian_confluence_repro.nu

atlassian-confluence-repro: require-browser-shell install-debug
	$(NU) tools/atlassian_confluence_repro.nu

uninstall: require-app-shell
	$(NU) tools/uninstall.nu

icons: require-icon-shell
	$(NU) tools/render_icons.nu

clean: require-nix-shell
	rm -rf '$(BUILD_DIR)'
