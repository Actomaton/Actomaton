PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iOS,iPhone \d\+ Pro [^M])
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,id=$(call udid_for,tvOS,TV)
PLATFORM_VISIONOS = visionOS Simulator,id=$(call udid_for,visionOS,Vision)
PLATFORM_WATCHOS = watchOS Simulator,id=$(call udid_for,watchOS,Watch)

SWIFT_TEST_FLAGS = $(if $(filter 1,$(TEST_CLOCK)),-Xswiftc -DTEST_CLOCK,)
SWIFTLY_SWIFT ?= swiftly run swift
SWIFTLY_TOOLCHAIN ?= 6.2.4
SWIFTLY_SELECTOR ?= +$(SWIFTLY_TOOLCHAIN)
SWIFTLY_TEST_FLAGS ?= -Xswiftc -DACTOMATON_ISOLATED_DEINIT_WORKAROUND
WASM_SWIFTLY ?= swiftly
WASM_SWIFT_TOOLCHAIN ?= 6.2.1
WASM_SWIFT_SDK ?= swift-6.2.1-RELEASE_wasm
WASM_SWIFT_INSTALL_FLAGS ?= --assume-yes
WASM_SDK_URL ?= https://download.swift.org/swift-6.2.1-release/wasm-sdk/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE_wasm.artifactbundle.tar.gz
WASM_SDK_CHECKSUM ?= 482b9f95462b87bedfafca94a092cf9ec4496671ca13b43745097122d20f18af
WASM_SWIFT ?= swiftly run swift
WASM_SWIFT_SELECTOR ?= +$(WASM_SWIFT_TOOLCHAIN)
WASM_BUILD_TARGETS = ActomatonCore ActomatonEffect Actomaton ActomatonDebugging ActomatonTesting
WASM_BUILD_TARGET_FLAGS = $(foreach target,$(WASM_BUILD_TARGETS),--target $(target))

# Base path after host name, required for GitHub Pages.
# Note that `documentation/{module_name}` is automatically added to the end of this path in Swift-DocC,
# e.g. https://actomaton.github.io/Actomaton/documentation/actomatonui/ .
DOC_HOSTING_BASE_PATH := /Actomaton

DOCBUILD_OUTPUT_DIR := docbuild

# e.g. `make xcode-build OS=iOS`
.PHONY: xcode-build
xcode-build:
	$(MAKE) _xcode ACTION="clean build"

# e.g. `make xcode-test OS=iOS`
# WARNING: Swift Concurrency does not work well on GitHub Actions Mac runners.
.PHONY: xcode-test
xcode-test:
	$(MAKE) _xcode ACTION="clean build test"

.PHONY: _xcode
_xcode:
	set -o pipefail && xcodebuild $(ACTION) -scheme Actomaton-Package -destination 'platform=$(PLATFORM_$(shell echo $(OS) | tr '[:lower:]' '[:upper:]'))' | xcpretty

.PHONY: linux-test
linux-test:
	docker run --rm -v "$$(pwd):/work" -w /work swift:6.2 bash -c \
		"apt-get update && apt-get install -y make && TEST_CLOCK=1 make swift-test"

.PHONY: swift-test
swift-test:
	swift test $(SWIFT_TEST_FLAGS)

.PHONY: swiftly-build
swiftly-build:
	$(SWIFTLY_SWIFT) build $(SWIFTLY_SELECTOR)

.PHONY: swiftly-test
swiftly-test:
	$(SWIFTLY_SWIFT) test $(SWIFT_TEST_FLAGS) $(SWIFTLY_TEST_FLAGS) $(SWIFTLY_SELECTOR)

.PHONY: wasm-install
wasm-install:
	brew install swiftly wasmtime
	$(WASM_SWIFTLY) init --no-modify-profile --skip-install --assume-yes
	$(WASM_SWIFTLY) install $(WASM_SWIFT_TOOLCHAIN) $(WASM_SWIFT_INSTALL_FLAGS)
	@if $(WASM_SWIFTLY) run swift sdk list $(WASM_SWIFT_SELECTOR) | awk 'BEGIN { found = 0 } $$0 == "$(WASM_SWIFT_SDK)" { found = 1 } END { exit(found ? 0 : 1) }'; then \
		echo "$(WASM_SWIFT_SDK) already installed"; \
	else \
		$(WASM_SWIFTLY) run swift sdk install \
			--checksum $(WASM_SDK_CHECKSUM) \
			$(WASM_SDK_URL) \
			$(WASM_SWIFT_SELECTOR); \
	fi

.PHONY: wasm-build
wasm-build:
	$(WASM_SWIFT) build --swift-sdk $(WASM_SWIFT_SDK) $(WASM_BUILD_TARGET_FLAGS) $(WASM_SWIFT_SELECTOR)

.PHONY: wasm-test
wasm-test:
	$(WASM_SWIFT) test --swift-sdk $(WASM_SWIFT_SDK) --disable-xctest --enable-swift-testing $(WASM_SWIFT_SELECTOR)

.PHONY: swiftformat
swiftformat:
	SWIFTFORMAT=1 swift package plugin --allow-writing-to-package-directory swiftformat

.PHONY: swiftformat-lint
swiftformat-lint:
	SWIFTFORMAT=1 swift package plugin --allow-writing-to-package-directory swiftformat --lint

#--------------------------------------------------
# DocC (combined documentation via swift-docc-plugin)
#--------------------------------------------------

.PHONY: docc
docc:
	$(MAKE) _docc DOC_HOSTING_BASE_PATH=$(DOC_HOSTING_BASE_PATH)

.PHONY: docc-local
docc-local:
	@# NOTE: `DOC_HOSTING_BASE_PATH=/` is only for local viewer, and does not work for GitHub Pages.
	$(MAKE) _docc DOC_HOSTING_BASE_PATH=/

	#--------------------------------------------------
	# Open http://localhost:8000/documentation
	#--------------------------------------------------
	python3 -m http.server 8000 -d $(DOCBUILD_OUTPUT_DIR)

.PHONY: _docc
_docc:
	rm -rf $(DOCBUILD_OUTPUT_DIR)

	DOCC=1 swift package \
		--allow-writing-to-directory $(DOCBUILD_OUTPUT_DIR) \
		generate-documentation \
		--enable-experimental-combined-documentation \
		--target Actomaton \
		--target ActomatonUI \
		--target ActomatonDebugging \
		--transform-for-static-hosting \
		--hosting-base-path $(DOC_HOSTING_BASE_PATH) \
		--output-path $(DOCBUILD_OUTPUT_DIR)

	@# Workaround: Create theme-settings.json if missing (required by DocC renderer).
	@# https://github.com/swiftlang/swift-docc-render/issues/1000
	@# Fix merged in swift-docc-render#1001 but not yet shipped in release toolchains.
	test -f $(DOCBUILD_OUTPUT_DIR)/theme-settings.json || echo '{}' > $(DOCBUILD_OUTPUT_DIR)/theme-settings.json

define udid_for
$(shell xcrun simctl list devices available '$(1)' | grep '$(2)' | sort -r | head -1 | awk -F '[()]' '{ print $$(NF-3) }')
endef
