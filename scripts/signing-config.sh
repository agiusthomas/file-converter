#!/bin/zsh
# Optional machine-local identifiers only; never store passwords or private keys.
converter_signing_file="$project_dir/Configuration/Signing.local.plist"
converter_signing_setting() {
  if [[ -f "$converter_signing_file" ]]; then
    /usr/bin/plutil -extract "$1" raw -o - "$converter_signing_file" 2>/dev/null || true
  fi
}
export CONVERTER_SIGN_IDENTITY="${CONVERTER_SIGN_IDENTITY:-$(converter_signing_setting identity)}"
export CONVERTER_DEVELOPMENT_TEAM="${CONVERTER_DEVELOPMENT_TEAM:-$(converter_signing_setting team)}"
export CONVERTER_NOTARY_PROFILE="${CONVERTER_NOTARY_PROFILE:-$(converter_signing_setting notaryProfile)}"
export CONVERTER_NOTARY_KEYCHAIN="${CONVERTER_NOTARY_KEYCHAIN:-$(converter_signing_setting notaryKeychain)}"
