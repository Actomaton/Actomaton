PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iOS,iPhone \d\+ Pro [^M])
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,id=$(call udid_for,tvOS,TV)
PLATFORM_VISIONOS = visionOS Simulator,id=$(call udid_for,visionOS,Vision)
PLATFORM_WATCHOS = watchOS Simulator,id=$(call udid_for,watchOS,Watch)

SWIFT_TEST_FLAGS = $(if $(filter 1,$(TEST_CLOCK)),-Xswiftc -DTEST_CLOCK,)

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

.PHONY: swift-test
swift-test:
	swift test $(SWIFT_TEST_FLAGS)

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
