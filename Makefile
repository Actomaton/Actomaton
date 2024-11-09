# NOTE: Async tests are currently disabled due to its indeterminacy nature of effectful computation.

PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iOS,iPhone \d\+ Pro [^M])
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,id=$(call udid_for,tvOS,TV)
PLATFORM_VISIONOS = visionOS Simulator,id=$(call udid_for,visionOS,Vision)
PLATFORM_WATCHOS = watchOS Simulator,id=$(call udid_for,watchOS,Watch)

# Base path after host name, required for GitHub Pages.
# Note that `documentation/{module_name}` is automatically added to the end of this path in Swift-DocC,
# e.g. https://actomaton.github.io/Actomaton/documentation/actomatonui/ .
DOC_HOSTING_BASE_PATH := /Actomaton

DOCBUILD_BUILD_DIR := .docbuild
DOCBUILD_PRODUCT_DIR := $(DOCBUILD_BUILD_DIR)/Build/Products/Debug-iphonesimulator
DOCBUILD_OUTPUT_DIR := docbuild

.PHONY: build-macOS
build-macOS:
	$(MAKE) build DESTINATION='$(PLATFORM_MACOS)'

.PHONY: build-iOS
build-iOS:
	$(MAKE) build DESTINATION='$(PLATFORM_IOS)'

.PHONY: build-watchOS
build-watchOS:
	$(MAKE) build DESTINATION='$(PLATFORM_WATCHOS)'

.PHONY: build-tvOS
build-tvOS:
	$(MAKE) build DESTINATION='$(PLATFORM_TVOS)'

.PHONY: build-macCatalyst
build-macCatalyst:
	$(MAKE) build DESTINATION='$(PLATFORM_MAC_CATALYST)'

.PHONY: build-visionOS
build-visionOS:
	$(MAKE) build DESTINATION='$(PLATFORM_VISIONOS)'

.PHONY: build
build:
	set -o pipefail && \
		xcodebuild build -scheme Actomaton-Package -destination 'platform=${DESTINATION}' | xcpretty

.PHONY: docs
docs:
	$(MAKE) _docs DOC_HOSTING_BASE_PATH=$(DOC_HOSTING_BASE_PATH)

.PHONY: docs-local
docs-local:
	@# NOTE: `DOC_HOSTING_BASE_PATH=/` is only for local viewer, and does not work for GitHub Pages.
	$(MAKE) _docs DOC_HOSTING_BASE_PATH=/

	#--------------------------------------------------
	# Open http://localhost:8000/documentation
	#--------------------------------------------------
	python3 -m http.server 8000 -d docbuild


# NOTE:
# `xcodebuild docbuild` allows spcifying iOS platform and generates dependency's doccarchives.
# https://forums.swift.org/t/generate-documentation-failing-on-import-uikit/55202/7
#
# NOTE: This task may fail once (Error 65), so in such case, retry.
.PHONY: _docs
_docs:
	@# Clean up.
	rm -rf $(DOCBUILD_BUILD_DIR) $(DOCBUILD_OUTPUT_DIR)

	xcodebuild docbuild \
		-scheme ActomatonUI \
		-destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
		-derivedDataPath $(DOCBUILD_BUILD_DIR) \
		OTHER_DOCC_FLAGS="--transform-for-static-hosting --hosting-base-path $(DOC_HOSTING_BASE_PATH)" \
		EXTRA_DOCC_FLAGS="--transform-for-static-hosting --hosting-base-path $(DOC_HOSTING_BASE_PATH)"

	@#--------------------------------------------------
	@# (Immaturely) gathering multiple doccarchives
	@#--------------------------------------------------
	@# Delete unnecessary DB files.
	find "$(DOCBUILD_PRODUCT_DIR)/Actomaton.doccarchive/index" -type f ! -name "index.json" -exec rm -f {} +
	find "$(DOCBUILD_PRODUCT_DIR)/ActomatonDebugging.doccarchive/index" -type f ! -name "index.json" -exec rm -f {} +
	find "$(DOCBUILD_PRODUCT_DIR)/ActomatonUI.doccarchive/index" -type f ! -name "index.json" -exec rm -f {} +

	@# Copy `ActomatonUI.doccarchive` to output_dir.
	cp -Rf $(DOCBUILD_PRODUCT_DIR)/ActomatonUI.doccarchive $(DOCBUILD_OUTPUT_DIR)

	@# Gather each module's `index/index.json` into output_dir's `./index/index-xxxxx.json`.
	jq . "$(DOCBUILD_PRODUCT_DIR)/Actomaton.doccarchive/index/index.json" > $(DOCBUILD_OUTPUT_DIR)/index/index-actomaton.json
	jq . "$(DOCBUILD_PRODUCT_DIR)/ActomatonDebugging.doccarchive/index/index.json" > $(DOCBUILD_OUTPUT_DIR)/index/index-actomatondebugging.json
	jq . "$(DOCBUILD_PRODUCT_DIR)/ActomatonUI.doccarchive/index/index.json" > $(DOCBUILD_OUTPUT_DIR)/index/index-actomatonui.json

	@# Merge each module's `index-xxxxx.json`s into a single `index.json`.
	jq -s '.[0].schemaVersion as $$schemaVersion | .[0].interfaceLanguages.swift[0] as $$file1 | .[1].interfaceLanguages.swift[0] as $$file2 | .[2].interfaceLanguages.swift[0] as $$file3 | { "interfaceLanguages": { "swift": [$$file1, $$file2, $$file3], "schemaVersion": $$schemaVersion } }' $(DOCBUILD_OUTPUT_DIR)/index/index-actomaton.json $(DOCBUILD_OUTPUT_DIR)/index/index-actomatondebugging.json $(DOCBUILD_OUTPUT_DIR)/index/index-actomatonui.json > $(DOCBUILD_OUTPUT_DIR)/index/index.json

	@# Gather each module's `./data/documentation` into output_dir.
	cp -rf $(DOCBUILD_PRODUCT_DIR)/Actomaton.doccarchive/data/documentation/* $(DOCBUILD_OUTPUT_DIR)/data/documentation/
	cp -rf $(DOCBUILD_PRODUCT_DIR)/ActomatonDebugging.doccarchive/data/documentation/* $(DOCBUILD_OUTPUT_DIR)/data/documentation/

	@# Gather each module's `./documentation` into output_dir.
	cp -rf $(DOCBUILD_PRODUCT_DIR)/Actomaton.doccarchive/documentation/* $(DOCBUILD_OUTPUT_DIR)/documentation/
	cp -rf $(DOCBUILD_PRODUCT_DIR)/ActomatonDebugging.doccarchive/documentation/* $(DOCBUILD_OUTPUT_DIR)/documentation/

	@# Clean up.
	rm -rf $(DOCBUILD_BUILD_DIR)

define udid_for
$(shell xcrun simctl list devices available '$(1)' | grep '$(2)' | sort -r | head -1 | awk -F '[()]' '{ print $$(NF-3) }')
endef
