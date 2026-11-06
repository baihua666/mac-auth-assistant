#!/usr/bin/env python3
"""Build-time version source. No private machine data is read or published."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def validate(value):
    pattern = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    if not isinstance(value.get("version"), str) or not re.fullmatch(pattern, value["version"]):
        raise ValueError("version must be a semantic version without build metadata")
    if "-" in value["version"]:
        for part in value["version"].split("-", 1)[1].split("."):
            if part.isdigit() and len(part) > 1 and part.startswith("0"):
                raise ValueError("numeric prerelease identifiers cannot have leading zeros")
    if type(value.get("build")) is not int or not 0 < value["build"] < 2_147_483_647:
        raise ValueError("build must be a positive integer")
    if not re.fullmatch(r"[1-9][0-9]*\.[0-9]+(?:\.[0-9]+)?", value.get("minimumMacOS", "")):
        raise ValueError("minimumMacOS must be a numeric macOS version")
    return value


def bump(value, part="patch", allow_series_change=False):
    if part in ["major", "minor"] and not allow_series_change:
        raise ValueError("only the last version component may increase; a series change requires --allow-series-change")
    result = dict(value)
    numbers = list(map(int, value["version"].split("-", 1)[0].split(".")))
    if part != "build":
        index = ["major", "minor", "patch"].index(part)
        numbers[index] += 1
        numbers[index + 1:] = [0] * (2 - index)
        result["version"] = ".".join(map(str, numbers))
    result["build"] += 1
    return validate(result)


def set_version(value, text, build, allow_series_change=False):
    if build <= value["build"]:
        raise ValueError("new build must increase")
    result = validate(dict(value, version=text, build=build))
    old = tuple(map(int, value["version"].split("-", 1)[0].split(".")))
    new = tuple(map(int, result["version"].split("-", 1)[0].split(".")))
    if new < old:
        raise ValueError("version cannot decrease")
    if new[:2] != old[:2] and not allow_series_change:
        raise ValueError("only the last version component may change; use --allow-series-change for an explicitly authorized exception")
    return result


def revision():
    result = subprocess.run(["git", "rev-parse", "--short=12", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        return "source"
    dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip() + ("-dirty" if dirty.stdout.strip() else "")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("show")
    check = commands.add_parser("check"); check.add_argument("--tag")
    change = commands.add_parser("bump"); change.add_argument("part", nargs="?", default="patch", choices=["major", "minor", "patch", "build"])
    change.add_argument("--allow-series-change", action="store_true")
    change = commands.add_parser("set"); change.add_argument("version"); change.add_argument("build", type=int)
    change.add_argument("--allow-series-change", action="store_true")
    render = commands.add_parser("render"); render.add_argument("--output", type=Path, required=True); render.add_argument("--unsigned", action="store_true")
    args = parser.parse_args()
    path = ROOT / "Version.json"
    value = validate(json.loads(path.read_text()))
    if args.command == "bump":
        value = bump(value, args.part, args.allow_series_change)
    if args.command == "set":
        value = set_version(value, args.version, args.build, args.allow_series_change)
    if args.command in ["bump", "set"]:
        path.write_text(json.dumps(value, indent=2) + "\n")
    if args.command == "check" and args.tag and args.tag != "v" + value["version"]:
        raise ValueError("tag does not match Version.json")
    if args.command == "render":
        info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        info.update(CFBundleShortVersionString=value["version"].split("-", 1)[0], CFBundleVersion=str(value["build"]),
                    LSMinimumSystemVersion=value["minimumMacOS"], MacAuthVersion=value["version"],
                    MacAuthSourceRevision=revision(), MacAuthBuildType="review" if args.unsigned else "signed")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(plistlib.dumps(info))
    print(json.dumps(value))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error))
