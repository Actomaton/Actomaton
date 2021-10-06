test-macOS:
	xcodebuild test -scheme Actomaton-Package -destination 'platform=OS X' | xcpretty

test-iOS:
	xcodebuild test -scheme Actomaton-Package -destination 'platform=iOS Simulator,name=iPhone 13 Pro' | xcpretty

test-watchOS:
	xcodebuild test -scheme Actomaton-Package -destination 'platform=watchOS Simulator,name=Apple Watch Series 7 - 45mm' | xcpretty

test-tvOS:
	xcodebuild test -scheme Actomaton-Package -destination 'platform=tvOS Simulator,name=Apple TV 4K' | xcpretty
