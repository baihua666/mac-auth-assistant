#!/bin/sh
# Detached, unprivileged whole-bundle replacement. All paths arrive as arguments.
set -eu
umask 077
update_pid="$1"
update_target="$2"
update_work="$3"
update_result="$4"
update_next="$update_work/next.app"
update_previous="$update_work/previous.app"
write_result() {
    printf '%s\n' "$1" > "$update_result.tmp"
    mv "$update_result.tmp" "$update_result"
}
write_result 'waitingForExit'
count=0
while /bin/kill -0 "$update_pid" 2>/dev/null; do
    count=$((count + 1))
    if [ "$count" -ge 60 ]; then
        write_result 'exitTimeout'
        exit 1
    fi
    /bin/sleep 1
done
if ! /usr/bin/codesign --verify --strict --test-requirement "$update_work/requirement.txt" "$update_next" ||
   ! /usr/bin/codesign --verify --strict --test-requirement "$update_work/requirement.txt" "$update_target"; then
    write_result 'signatureRejected'
    /usr/bin/open -g "$update_target" || true
    exit 1
fi
if ! mv "$update_target" "$update_previous"; then
    write_result 'replaceFailed'
    /usr/bin/open -g "$update_target" || true
    exit 1
fi
if ! mv "$update_next" "$update_target"; then
    if ! mv "$update_previous" "$update_target"; then
        write_result 'rollbackFailed'
        exit 1
    fi
    write_result 'rolledBack'
    /usr/bin/open -g "$update_target" || true
    exit 1
fi
if ! /usr/bin/codesign --verify --strict --test-requirement "$update_work/requirement.txt" "$update_target"; then
    if ! mv "$update_target" "$update_work/rejected.app" || ! mv "$update_previous" "$update_target"; then
        write_result 'rollbackFailed'
        exit 1
    fi
    write_result 'rolledBack'
    /usr/bin/open -g "$update_target" || true
    exit 1
fi
write_result 'installed'
if ! /usr/bin/open -g "$update_target"; then
    if ! mv "$update_target" "$update_work/rejected.app" || ! mv "$update_previous" "$update_target"; then
        write_result 'rollbackFailed'
        exit 1
    fi
    write_result 'rolledBack'
    /usr/bin/open -g "$update_target" || true
    exit 1
fi
# Keep previous.app locally for manual recovery; never include this directory in releases.
exit 0
