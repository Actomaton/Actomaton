test-macOS:
	$(MAKE) test DESTINATION='platform=OS X'

test-iOS:
	$(MAKE) test DESTINATION='platform=iOS Simulator,name=iPhone 13 Pro'

test-watchOS:
	$(MAKE) test DESTINATION='platform=watchOS Simulator,name=Apple Watch Series 7 - 45mm'

test-tvOS:
	$(MAKE) test DESTINATION='platform=tvOS Simulator,name=Apple TV 4K'

test:
	set -o pipefail && \
		xcodebuild test -scheme Actomaton-Package -destination '${DESTINATION}' | xcpretty
