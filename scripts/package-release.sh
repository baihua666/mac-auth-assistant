#!/bin/bash
# Produces public app artifacts only; publishing is a separate explicit action.
set -euo pipefail
release_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$release_root"
release_version="$(python3 -c 'import json; print(json.load(open("Version.json"))["version"])')"
python3 scripts/version.py check --tag "$(git describe --tags --exact-match)"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    printf '%s\n' 'Commit the reviewed source before packaging a release.' >&2
    exit 1
fi
bash build-app.sh
release_build="$(python3 -c 'import json; print(json.load(open("Version.json"))["build"])')"
release_arch="$(uname -m)"
release_name="MacAuthAssistant-${release_version}-b${release_build}-${release_arch}.zip"
/usr/bin/codesign --verify --strict dist/MacAuthAssistant.app
/usr/bin/ditto -c -k --norsrc --keepParent dist/MacAuthAssistant.app "dist/$release_name"
(cd dist && /usr/bin/shasum -a 256 "$release_name" > SHA256SUMS)
printf '%s\n' "dist/$release_name" 'dist/SHA256SUMS'
