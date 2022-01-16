# NOTE: Async tests are currently disabled due to its indeterminacy nature of effectful computation.

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
	$(MAKE) build DESTINATION='platform=tvOS Simulator,name=Apple TV 4K'

.PHONY: build
build:
	set -o pipefail && \
		xcodebuild build -scheme Actomaton-Package -destination '${DESTINATION}' | xcpretty
