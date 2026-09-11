#!/usr/bin/env bash
# Builds the signed App Store IPA and uploads it to TestFlight, the same
# way the multipass runbook does (docs/runbooks/RELEASE.md there):
# automatic signing on team 73W98CESN9, app-store-connect export through
# ios/ExportOptions.plist, altool upload as syndalis@mac.com with an
# app-specific password. The password is read from the gitignored
# .env.asc (BOARDHOP_ASC_PASSWORD) when that file exists, else from the
# multipass repo's .env (MULTIPASS_ASC_PASSWORD, same Apple ID); it is
# never printed.
#
#   tool/ship-ios.sh <build-number> [--skip-build]
#
# The build number must go up on every upload (App Store Connect rejects
# duplicates); the marketing version is pubspec.yaml's `version`. Needs
# the Boardhop app record to exist in App Store Connect (bundle id
# com.kammcs.boardhop); until then altool answers "No suitable
# application records were found".
set -euo pipefail
cd "$(dirname "$0")/.."

build=${1:?usage: tool/ship-ios.sh <build-number> [--skip-build]}
skip=${2:-}
version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
ipa=build/ios/ipa/boardhop.ipa

if [ "$skip" != "--skip-build" ]; then
  flutter build ipa --release \
    --dart-define-from-file=.env \
    --export-options-plist=ios/ExportOptions.plist \
    --build-name="$version" --build-number="$build"
fi
[ -f "$ipa" ] || { echo "no IPA at $ipa" >&2; exit 1; }

# Cheap guard from the multipass runbook: the entitlements survived the
# store export (the MSAL keychain group).
rm -rf build/ios/ipa/verify && mkdir -p build/ios/ipa/verify
unzip -q "$ipa" -d build/ios/ipa/verify
codesign -d --entitlements :- build/ios/ipa/verify/Payload/Runner.app 2>/dev/null \
  | plutil -p - | grep -E "keychain-access-groups|application-identifier|adalcache" || true

if [ -f .env.asc ]; then
  BOARDHOP_ASC_PASSWORD=$(sed -n 's/^BOARDHOP_ASC_PASSWORD=//p' .env.asc)
else
  BOARDHOP_ASC_PASSWORD=$(sed -n 's/^MULTIPASS_ASC_PASSWORD=//p' ../multipass-theater/.env)
fi
[ -n "$BOARDHOP_ASC_PASSWORD" ] || { echo "no app-specific password found" >&2; exit 1; }
export BOARDHOP_ASC_PASSWORD
xcrun altool --upload-app -t ios -f "$ipa" \
  -u syndalis@mac.com -p @env:BOARDHOP_ASC_PASSWORD
echo "uploaded $version ($build); TestFlight processes it in a few minutes"
