#!/usr/bin/env bash
# Archives Busk, signs it with cloud-managed certificates via the App Store Connect API key, and uploads it
# to TestFlight (TestFlight only: this never submits for App Store review).
#
# Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 (the .p8 contents) in the environment.
# Optional: BUILD_NUMBER (default: latest TestFlight build + 1), APPLE_TEAM_ID (default: read from the API).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_P8:?}"
BUNDLE_ID=com.potatoman03.busk
OUT=build/testflight
rm -rf "$OUT" && mkdir -p "$OUT/keys"
trap 'rm -rf "$OUT/keys"' EXIT

JWT=$(swift scripts/asc_jwt.swift)
api() { curl -sfg -H "Authorization: Bearer $JWT" "https://api.appstoreconnect.apple.com$1"; }

TEAM_ID=${APPLE_TEAM_ID:-$(api "/v1/bundleIds?filter[identifier]=$BUNDLE_ID" | jq -r '.data[0].attributes.seedId')}
APP_ID=$(api "/v1/apps?filter[bundleId]=$BUNDLE_ID" | jq -r '.data[0].id // empty')
[ -n "$APP_ID" ] || { echo "No App Store Connect app record for $BUNDLE_ID yet" >&2; exit 1; }
if [ -z "${BUILD_NUMBER:-}" ]; then
  LAST=$(api "/v1/builds?filter[app]=$APP_ID&sort=-uploadedDate&limit=1" | jq -r '.data[0].attributes.version // "0"')
  BUILD_NUMBER=$(( ${LAST%%.*} + 1 ))
fi
echo "Team $TEAM_ID, app $APP_ID, build $BUILD_NUMBER"

# Keep the key file inside the build dir and pass the PEM rebuilt by asc_jwt.swift's rules.
KEY="$OUT/keys/AuthKey_${ASC_KEY_ID}.p8"
python3 - "$KEY" <<'PY'
import os, re, sys, textwrap
body = re.sub(r"-----(BEGIN|END) PRIVATE KEY-----|\\n|\s", "", os.environ["ASC_KEY_P8"])
open(sys.argv[1], "w").write("-----BEGIN PRIVATE KEY-----\n" + "\n".join(textwrap.wrap(body, 64)) + "\n-----END PRIVATE KEY-----\n")
PY
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$PWD/$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

xcodebuild archive -project Busk.xcodeproj -scheme Busk -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Busk.xcarchive" "${AUTH[@]}" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION="$BUILD_NUMBER" | tail -5

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>${EXPORT_DESTINATION:-upload}</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>testFlightInternalTestingOnly</key><true/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$OUT/Busk.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" "${AUTH[@]}" | tail -5
echo "Busk build $BUILD_NUMBER: ${EXPORT_DESTINATION:-upload} done"
