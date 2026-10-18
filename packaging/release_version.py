import argparse
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(
    r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?",
    re.ASCII,
)


def latest_version(changelog):
    headings = re.findall(r"^## \[(.+?)\](.*)$", changelog.read_text(encoding="utf-8"), re.MULTILINE)
    if not headings or headings[0] != ("Unreleased", ""):
        raise ValueError("CHANGELOG.md must start with ## [Unreleased]")
    if len(headings) < 2 or not SEMVER.fullmatch(headings[1][0]):
        raise ValueError("add a dated Semantic Versioning release below Unreleased first")
    return headings[1][0]


def stamp_project(stage, version):
    project = stage / "project.godot"
    text = project.read_text(encoding="utf-8")
    sections = list(re.finditer(r"^\[([^\]]+)\]$", text, re.MULTILINE))
    application = next((i for i, section in enumerate(sections) if section[1] == "application"), None)
    if application is None:
        raise ValueError("project.godot has no application section")
    section = sections[application]
    end = sections[application + 1].start() if application + 1 < len(sections) else len(text)
    body = re.sub(r'^config/version=.*\n?', '', text[section.end():end], flags=re.MULTILINE)
    project.write_text(text[:section.end()] + f'\nconfig/version="{version}"\n' + body + text[end:], encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version", nargs="?")
    parser.add_argument("--stage", type=Path)
    args = parser.parse_args()
    try:
        version = args.version or latest_version(ROOT / "CHANGELOG.md")
        if not SEMVER.fullmatch(version):
            raise ValueError("version must follow Semantic Versioning")
        if any(int(part) > 65535 for part in version.split("-")[0].split("+")[0].split(".")):
            raise ValueError("Windows version components must be at most 65535")
        if args.stage:
            stamp_project(args.stage, version)
        print(version)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
