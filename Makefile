# NOTE: Async tests are currently disabled due to its indeterminacy nature of effectful computation.

DOC_HOSTING_BASE_PATH := /Actomaton
DOCBUILD_BUILD_DIR := .docbuild
DOCBUILD_PRODUCT_DIR := $(DOCBUILD_BUILD_DIR)/Build/Products/Debug-iphonesimulator
DOCBUILD_OUTPUT_DIR := docbuild

.PHONY: build-macOS
build-macOS:
	$(MAKE) build DESTINATION='platform=OS X'

.PHONY: build-iOS
build-iOS:
	$(MAKE) build DESTINATION='platform=iOS Simulator,name=iPhone 13 Pro'

.PHONY: build-watchOS
build-watchOS:
	$(MAKE) build DESTINATION='platform=watchOS Simulator,name=Apple Watch Series 7 - 45mm'

.PHONY: build-tvOS
build-tvOS:
	$(MAKE) build DESTINATION='platform=tvOS Simulator,name=Apple TV 4K (at 1080p) (2nd generation)'

.PHONY: build
build:
	set -o pipefail && \
		xcodebuild build -scheme Actomaton-Package -destination '${DESTINATION}' | xcpretty

# NOTE:
# `xcodebuild docbuild` allows spcifying iOS platform and generates dependency's doccarchives.
# https://forums.swift.org/t/generate-documentation-failing-on-import-uikit/55202/7
#
# NOTE: This task may fail once (Error 65), so in such case, retry.
.PHONY: docs
docs:
	xcodebuild docbuild \
		-scheme ActomatonUI \
		-destination 'platform=iOS Simulator,name=iPhone 13 Pro' \
		-derivedDataPath $(DOCBUILD_BUILD_DIR) \
		OTHER_DOCC_FLAGS="--transform-for-static-hosting --hosting-base-path $(DOC_HOSTING_BASE_PATH)"

	#--------------------------------------------------
	# (Immaturely) gathering multiple doccarchives
	#--------------------------------------------------
	# Gather `./data/documentation` from other packages into ActomatonUI.
	cp -rf $(DOCBUILD_PRODUCT_DIR)/Actomaton.doccarchive/data/documentation/* $(DOCBUILD_PRODUCT_DIR)/ActomatonUI.doccarchive/data/documentation/
	cp -rf $(DOCBUILD_PRODUCT_DIR)/ActomatonDebugging.doccarchive/data/documentation/* $(DOCBUILD_PRODUCT_DIR)/ActomatonUI.doccarchive/data/documentation/

	# Gather `./documentation` from other packages into ActomatonUI.
	cp -rf $(DOCBUILD_PRODUCT_DIR)/Actomaton.doccarchive/documentation/* $(DOCBUILD_PRODUCT_DIR)/ActomatonUI.doccarchive/documentation/
	cp -rf $(DOCBUILD_PRODUCT_DIR)/ActomatonDebugging.doccarchive/documentation/* $(DOCBUILD_PRODUCT_DIR)/ActomatonUI.doccarchive/documentation/

	# Delete unnecessary DB files.
	rm -rf $(DOCBUILD_PRODUCT_DIR)/ActomatonUI.doccarchive/index/

	# Move `ActomatonUI.doccarchive` to `$(DOCBUILD_OUTPUT_DIR)`.
	mv -f $(DOCBUILD_PRODUCT_DIR)/ActomatonUI.doccarchive $(DOCBUILD_OUTPUT_DIR)

	# Clean up `$(DOCBUILD_BUILD_DIR)`.
	rm -rf $(DOCBUILD_BUILD_DIR)
