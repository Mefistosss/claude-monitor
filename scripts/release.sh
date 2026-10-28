#!/usr/bin/env bash
# Builds a Developer ID-signed, notarized and stapled DMG of Claude Monitor.
#
# Usage:
#   scripts/release.sh            # build dist/ClaudeMonitor-<version>.dmg
#   scripts/release.sh --publish  # also create GitHub release v<version> with the DMG
#
# One-time setup:
#   1. Developer ID Application certificate in the login Keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. Notarization credentials saved in the Keychain:
#      xcrun notarytool store-credentials claude-monitor \
#        --apple-id <apple-id> --team-id 89X7GT8Y93 --password <app-specific-password>
#      (app-specific password: https://account.apple.com → Sign-In and Security)
#
# Environment:
#   NOTARY_PROFILE  notarytool keychain profile (default: claude-monitor)
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID=89X7GT8Y93
SCHEME=ClaudeMonitor
APP_NAME="Claude Monitor"
NOTARY_PROFILE="${NOTARY_PROFILE:-claude-monitor}"
PUBLISH=false
[[ "${1:-}" == "--publish" ]] && PUBLISH=true

BUILD_DIR=build/release
DIST_DIR=dist
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

step "Checking prerequisites"
security find-identity -v -p codesigning | grep -q "Developer ID Application: .*($TEAM_ID)" \
  || fail "No 'Developer ID Application' certificate for team $TEAM_ID in the Keychain (see setup in $0)."
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "notarytool profile '$NOTARY_PROFILE' not found or invalid (see setup in $0)."
if $PUBLISH; then
  command -v gh >/dev/null || fail "gh CLI is required for --publish."
  [[ -z "$(git status --porcelain)" ]] || fail "Working tree is not clean; commit before publishing."
  git fetch --quiet origin
  [[ -n "$(git branch -r --contains HEAD)" ]] || fail "HEAD is not pushed to origin; push before publishing."
fi
if command -v xcodegen >/dev/null; then
  xcodegen generate --quiet
fi

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml | head -1)
[[ -n "$VERSION" ]] || fail "Could not read MARKETING_VERSION from project.yml."
DMG="$DIST_DIR/ClaudeMonitor-$VERSION.dmg"
echo "Version: $VERSION"

rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR" "$DIST_DIR"

step "Archiving"
xcodebuild archive \
  -project ClaudeMonitor.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -quiet

step "Exporting with Developer ID"
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -quiet
APP="$EXPORT_DIR/$APP_NAME.app"
codesign --verify --deep --strict "$APP"

step "Creating DMG"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" -quiet
SIGN_IDENTITY=$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\"/\1/p" | head -1)
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

step "Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

shasum -a 256 "$DMG" | tee "$DMG.sha256"

if $PUBLISH; then
  step "Publishing GitHub release v$VERSION"
  gh release create "v$VERSION" "$DMG" "$DMG.sha256" \
    --target "$(git rev-parse HEAD)" \
    --title "Claude Monitor $VERSION" \
    --generate-notes
fi

step "Done: $DMG"
