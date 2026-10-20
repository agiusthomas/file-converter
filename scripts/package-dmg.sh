#!/bin/zsh
# Package an already signed and notarized app without changing its contents.
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
source "$project_dir/scripts/signing-config.sh"
: "${CONVERTER_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
: "${CONVERTER_NOTARY_PROFILE:?Set an existing notarytool keychain profile name}"
[[ "$CONVERTER_SIGN_IDENTITY" != "-" ]] || { print -u2 "DMG releases require Developer ID signing"; exit 2; }
app_dir="$project_dir/build/Glacier File Converter.app"
version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_dir/Contents/Info.plist")"
[[ "$version" == [0-9]* && "$version" != *[^0-9.]* ]] || { print -u2 "Invalid app version"; exit 2; }
codesign --verify --deep --strict "$app_dir"
xcrun stapler validate "$app_dir"
spctl --assess --type execute --verbose "$app_dir"
staging_dir="$(mktemp -d "$project_dir/build/dmg-staging.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$app_dir" "$staging_dir/Glacier File Converter.app"
ln -s /Applications "$staging_dir/Applications"
cp docs/INSTALLATION.md "$staging_dir/Install Glacier File Converter.txt"
dmg="$project_dir/build/Glacier-File-Converter-$version.dmg"
hdiutil create -volname "Glacier File Converter" -srcfolder "$staging_dir" -format UDZO -fs HFS+ -ov "$dmg"
codesign --force --timestamp --sign "$CONVERTER_SIGN_IDENTITY" "$dmg"
notary_arguments=(--keychain-profile "$CONVERTER_NOTARY_PROFILE")
if [[ -n "$CONVERTER_NOTARY_KEYCHAIN" ]]; then notary_arguments+=(--keychain "$CONVERTER_NOTARY_KEYCHAIN"); fi
xcrun notarytool submit "$dmg" "${notary_arguments[@]}" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
hdiutil verify "$dmg"
print -r -- "$dmg"
