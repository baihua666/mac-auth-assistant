#!/usr/bin/env python3
"""Check the entire Git index before publishing. Never prints matched secrets."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
result = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, check=True)
files = [name for name in result.stdout.decode().split("\0") if name]
forbidden = re.compile(r"^(?:\.local/|\.build/|dist/|\.signing-identity\.local$|signing-identity\.txt$|\.env(?:\.|$))|\.(?:p12|pfx|key|mobileprovision)$")
patterns = [re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
            re.compile(rb"\b(?:ghp_|gho_|github_pat_)[A-Za-z0-9_]{25,}\b"),
            re.compile(rb"/Users/[A-Za-z0-9_.-]+/")]
problems = []
for name in files:
    path = root / name
    # Read staged bytes, the exact content Git will publish.
    data = subprocess.run(["git", "show", ":" + name], cwd=root, capture_output=True, check=True).stdout
    if forbidden.search(name) or path.is_symlink() or any(pattern.search(data) for pattern in patterns):
        problems.append(name)
if problems:
    raise SystemExit("Refusing to publish private content in: " + ", ".join(problems))
print(f"Public source check passed ({len(files)} files).")
