#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 -m unittest discover -s backend/tests -v
swift test --disable-sandbox
# -disable-sandbox applies to compiler macro subprocesses inside this environment.
xcodebuild -project ios/TwoTogether.xcodeproj -scheme TwoTogether \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS=-disable-sandbox build
