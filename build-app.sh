#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
cd "$task_root"
task_unsigned=false
case "${1:-}" in
    "") ;;
    --unsigned) task_unsigned=true ;;
    *) printf '%s\n' 'Usage: bash build-app.sh [--unsigned]' >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then
    printf '%s\n' 'Usage: bash build-app.sh [--unsigned]' >&2
    exit 1
fi
task_signing_identity="${MAC_AUTH_SIGNING_IDENTITY:-}"
if [[ -z "$task_signing_identity" && -f "$task_root/.signing-identity.local" ]]; then
    task_signing_identity="$(cat "$task_root/.signing-identity.local")"
fi
if [[ "$task_unsigned" == false ]]; then
    if [[ ! "$task_signing_identity" =~ ^[A-Fa-f0-9]{40}$ ]]; then
        printf '%s\n' '需要固定签名证书的 SHA-1；禁止回退到 ad-hoc 签名，以免更新后权限失效。' >&2
        exit 1
    fi
    /usr/bin/security find-identity -v -p codesigning | /usr/bin/awk -v identity="$task_signing_identity" \
        'toupper($2) == toupper(identity) && $0 !~ /CSSMERR_/ { found=1 } END { exit !found }' || {
        printf '%s\n' '未找到指定的有效签名证书及私钥；请设置 MAC_AUTH_SIGNING_IDENTITY，不能临时更换签名身份。' >&2
        exit 1
    }
fi
swift build -c release
task_bin_dir="$(swift build -c release --show-bin-path)"
task_app="$task_root/dist/MacAuthAssistant.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
# Remove signatures from earlier output so unsigned builds cannot retain a stale seal.
rm -rf "$task_app/Contents/_CodeSignature"
cp "$task_bin_dir/MacAuthAssistant" "$task_app/Contents/MacOS/MacAuthAssistant"
if [[ "$task_unsigned" == true ]]; then
    python3 "$task_root/scripts/version.py" render --output "$task_app/Contents/Info.plist" --unsigned
else
    python3 "$task_root/scripts/version.py" render --output "$task_app/Contents/Info.plist"
fi
cp "$task_root/Resources/InstallUpdate.sh" "$task_app/Contents/Resources/InstallUpdate.sh"
if [[ "$task_unsigned" == false ]]; then
    /usr/bin/codesign --force --sign "$task_signing_identity" --timestamp=none --identifier local.mac-auth-assistant "$task_app"
    /usr/bin/codesign --verify --strict "$task_app"
else
    printf '%s\n' 'Unsigned review build only; use a stable certificate before installing for automation.' >&2
fi
printf '%s\n' "$task_app"
