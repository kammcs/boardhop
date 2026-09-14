#!/usr/bin/env bash
# Builds the signed release AAB and uploads it to the Google Play internal
# track, the same way the multipass runbook does (docs/runbooks/RELEASE.md
# there): upload key in the gitignored android/keystore/ (passwords in
# android/keystore.properties), Play App Signing on Google's side, and
# fastlane supply with the Play Developer API service account JSON at
# android/keystore/play-service-account.json. Nothing here prints a secret.
#
#   tool/ship-android.sh <build-number> [--skip-build] [--track internal|closed|production]
#
# The build number is Play's versionCode and must go up on every upload;
# the version name is pubspec.yaml's `version`. It shares the counter with
# tool/ship-ios.sh so one number names one build on both stores. Needs the
# Boardhop app record to exist in Play Console and the service account
# invited on it with "Release to testing tracks".
set -euo pipefail
cd "$(dirname "$0")/.."

build=${1:?usage: tool/ship-android.sh <build-number> [--skip-build] [--track <track>]}
shift
skip=false
track=internal
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) skip=true ;;
    --track) track=${2:?--track needs a value}; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
aab=build/app/outputs/bundle/release/app-release.aab

[ -f android/keystore.properties ] || { echo "android/keystore.properties is missing (upload key)" >&2; exit 1; }
[ -f android/keystore/play-service-account.json ] || { echo "android/keystore/play-service-account.json is missing" >&2; exit 1; }

# The MSAL redirect must name the certificate the *installed* app carries,
# which for a Play install is Google's app signing key, not the upload key
# (research/09 A5). android/secret.properties holds that hash for the
# manifest; Dart needs the same value, so it goes in as a define here rather
# than defaulting to the debug hash and failing at client creation.
hash=$(sed -n 's/^MSAL_RELEASE_SIGNATURE_HASH=//p' android/secret.properties)
[ -n "$hash" ] || { echo "MSAL_RELEASE_SIGNATURE_HASH is missing from android/secret.properties" >&2; exit 1; }
redirect="msauth://com.kammcs.boardhop/$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$hash")"

if [ "$skip" = false ]; then
  flutter build appbundle --release \
    --dart-define-from-file=.env \
    --dart-define="BOARDHOP_ANDROID_REDIRECT_URI=$redirect" \
    --build-name="$version" --build-number="$build"
fi
[ -f "$aab" ] || { echo "no AAB at $aab" >&2; exit 1; }

# Cheap guard: the bundle is signed with the upload key, not the debug key.
signer=$(keytool -printcert -jarfile "$aab" 2>/dev/null | sed -n 's/^Owner: //p' | head -1)
case "$signer" in
  *"Boardhop upload"*) ;;
  *) echo "AAB is not signed with the upload key (signer: ${signer:-none})" >&2; exit 1 ;;
esac

# Never through head/tail (the multipass lesson: you get the pipe's exit
# status); fastlane/report.xml has the per-step result if it goes wrong.
(cd android && fastlane internal track:"$track")
echo "uploaded $version ($build) to the Play $track track"
