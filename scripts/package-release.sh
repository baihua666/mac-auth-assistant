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
bash build-app.sh --universal
release_build="$(python3 -c 'import json; print(json.load(open("Version.json"))["build"])')"
release_arch=universal
release_name="MacAuthAssistant-${release_version}-b${release_build}-${release_arch}.zip"
/usr/bin/codesign --verify --strict dist/MacAuthAssistant.app
python3 - <<'PY'
from pathlib import Path
import re
app = Path('dist/MacAuthAssistant.app')
expected = {'Contents/Info.plist', 'Contents/MacOS/MacAuthAssistant',
            'Contents/Resources/InstallUpdate.sh', 'Contents/_CodeSignature/CodeResources'}
entries = list(app.rglob('*'))
files = {str(path.relative_to(app)) for path in entries if path.is_file()}
if files != expected or any(path.is_symlink() for path in entries):
    raise SystemExit('Release bundle contains unexpected files or links; review before publishing.')
for path in entries:
    if not path.is_file():
        continue
    data = path.read_bytes()
    if re.search(rb'/Users/[A-Za-z0-9_.-]+/|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:ghp_|gho_|github_pat_)[A-Za-z0-9_]{25,}', data):
        raise SystemExit('Release bundle privacy check failed; refusing to package.')
print('Release bundle privacy check passed.')
PY
/usr/bin/ditto -c -k --norsrc --keepParent dist/MacAuthAssistant.app "dist/$release_name"
(cd dist && /usr/bin/shasum -a 256 "$release_name" > SHA256SUMS)
printf '%s\n' "dist/$release_name" 'dist/SHA256SUMS'
