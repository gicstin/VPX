import argparse
from datetime import date
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

from release_version import SEMVER, latest_version


ROOT = Path(__file__).resolve().parents[1]
CATEGORIES = {"Added", "Changed", "Fixed", "Removed", "Deprecated", "Security"}
ASSETS = {"windows": "VPX-windows-x86_64.exe", "linux": "VPX-linux-x86_64.AppImage"}


def release_notes(path, version):
    text = path.read_text(encoding="utf-8")
    headings = list(re.finditer(r"^## (.+)$", text, re.MULTILINE))
    matches = []
    for index, heading in enumerate(headings):
        if heading.group(1).startswith(f"[{version}]"):
            end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
            matches.append((heading.group(1), text[heading.end():end].strip()))
    if len(matches) != 1:
        raise ValueError(f"{path}: need exactly one ## [{version}] - YYYY-MM-DD section; move Unreleased notes there first")
    heading, body = matches[0]
    if not re.fullmatch(rf"\[{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}", heading):
        raise ValueError(f"invalid release heading: {heading}")
    date.fromisoformat(heading.rsplit(" - ", 1)[1])
    if not headings or headings[0].group(1) != "[Unreleased]":
        raise ValueError("CHANGELOG.md must start with ## [Unreleased] before release sections")
    category = None
    bullets = 0
    in_bullet = False
    for line in body.splitlines():
        if not line.strip():
            continue
        if line.startswith("### "):
            category = line[4:]
            in_bullet = False
            if category not in CATEGORIES:
                raise ValueError(f"unsupported changelog category: {category}")
        elif line.startswith("- ") and line[2:].strip() and category:
            bullets += 1
            in_bullet = True
        elif in_bullet and line.startswith("  ") and not re.match(r"\s*(?:[-*+] |\d+[.)] )", line):
            continue
        elif category is None and not bullets and not line.startswith(("#", "-", "*", "+")):
            continue
        else:
            raise ValueError(f"release notes must use categories and one bullet per change: {line}")
    if not bullets:
        raise ValueError(f"no release notes for {version}")
    return body + "\n"


def compiled_asset(path, platform):
    path = path.resolve()
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"missing or empty {platform} package: {path}")
    suffix = ".exe" if platform == "windows" else ".AppImage"
    magic = b"MZ" if platform == "windows" else b"\x7fELF"
    with path.open("rb") as stream:
        if path.suffix != suffix or stream.read(len(magic)) != magic:
            raise ValueError(f"expected a compiled {suffix} package: {path}")
    return path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_output(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=ROOT, text=True).strip()


def source_commit():
    if git_output("status", "--porcelain", "--untracked-files=normal"):
        raise ValueError("working tree has changes; commit release sources yourself before publishing, or use --build-only")
    return git_output("rev-parse", "HEAD")


def github_preflight(repo, tag, commit):
    subprocess.run(["gh", "auth", "status"], check=True)
    try:
        remote_commit = subprocess.check_output(
            ["gh", "api", f"repos/{repo}/commits/{commit}", "--jq", ".sha"], text=True,
        ).strip()
    except subprocess.CalledProcessError as error:
        raise ValueError("cannot find source commit on GitHub; check repository access and push release sources yourself first") from error
    if remote_commit != commit:
        raise ValueError("release source commit must already exist on GitHub; push it yourself first")
    refs = subprocess.check_output(
        ["git", "ls-remote", f"https://github.com/{repo}.git", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}"], text=True,
    ).splitlines()
    if refs and refs[-1].split()[0] != commit:
        raise ValueError(f"remote tag {tag} points to another commit")
    releases = subprocess.check_output(
        ["gh", "api", "--paginate", f"repos/{repo}/releases", "--jq", ".[].tag_name"], text=True,
    ).splitlines()
    if tag in releases:
        raise ValueError(f"release {tag} already exists; choose a new version or finish its draft on GitHub")


def build_packages(args, version):
    environment = {**os.environ, "VPX_VERSION": version, "VPX_DIST_DIR": str(args.dist.resolve())}
    environment.pop("VPX_BUILD_DIR", None)
    for script in ["linux/build-appimage.sh", "windows/build-windows.sh"]:
        command = ["bash", str(ROOT / "packaging" / script)]
        if args.jobs:
            command += ["-j", str(args.jobs)]
        print(shlex.join(command), flush=True)
        if not args.dry_run:
            args.dist.mkdir(parents=True, exist_ok=True)
            filename = f"VPX-{version}-windows-x86_64.exe" if script.startswith("windows/") else f"VPX-{version}-x86_64.AppImage"
            (args.dist / filename).unlink(missing_ok=True)
            subprocess.run(command, cwd=ROOT, env=environment, check=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build and publish VPX Windows/Linux releases using the changelog version and gh.")
    parser.add_argument("version", nargs="?", help="Semantic version, e.g. 1.2.3 or v1.2.3")
    parser.add_argument("--build", action="store_true", help="compile both platforms before upload (Linux x86_64 host)")
    parser.add_argument("--build-only", action="store_true", help="compile both platforms without contacting GitHub")
    parser.add_argument("-j", "--jobs", type=int, help="parallel compiler jobs")
    parser.add_argument("--repo", default="gicstin/VPX", help="GitHub OWNER/REPO (default: gicstin/VPX)")
    parser.add_argument("--dist", type=Path, default=ROOT / "dist", help="package directory; --build writes into its vVERSION subdirectory")
    parser.add_argument("--windows", type=Path, help="explicit Windows .exe path")
    parser.add_argument("--linux", type=Path, help="explicit Linux .AppImage path")
    parser.add_argument("--changelog", type=Path, default=ROOT / "CHANGELOG.md")
    parser.add_argument("--draft", action="store_true", help="upload as a draft for review")
    parser.add_argument("--dry-run", action="store_true", help="validate and preview locally without contacting GitHub")
    args = parser.parse_args(argv)
    if args.jobs is not None and args.jobs < 1:
        parser.error("--jobs must be positive")
    args.build = args.build or args.build_only
    if args.build and (args.windows or args.linux):
        parser.error("--build cannot use precompiled --windows or --linux packages")
    try:
        version = args.version.removeprefix("v") if args.version else latest_version(args.changelog)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    semver = SEMVER.fullmatch(version)
    if not semver:
        parser.error("version must follow Semantic Versioning, e.g. 1.2.3 or 1.2.3-rc.1")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        parser.error("--repo must be GitHub OWNER/REPO")
    try:
        notes = release_notes(args.changelog, version)
        commit = None
        if args.build:
            if not sys.platform.startswith("linux") or os.uname().machine != "x86_64":
                raise ValueError("release builds require a Linux x86_64 host")
            if not args.build_only and not args.dry_run:
                if shutil.which("gh") is None:
                    raise ValueError("GitHub CLI (gh) is required; install it and run gh auth login")
                commit = source_commit()
                github_preflight(args.repo, f"v{version}", commit)
            print(f"VPX {version} -> {args.repo}", flush=True)
            args.dist = args.dist / f"v{version}"
            build_packages(args, version)
            if args.dry_run:
                action = "keep packages locally" if args.build_only else f"create v{version} at HEAD and upload README-compatible assets"
                print(f"Preview only. Would build both platforms and {action}.")
                return 0
            if commit and source_commit() != commit:
                raise ValueError("source changed during compilation; release aborted")
        sources = {
            "windows": compiled_asset(args.windows or args.dist / f"VPX-{version}-windows-x86_64.exe", "windows"),
            "linux": compiled_asset(args.linux or args.dist / f"VPX-{version}-x86_64.AppImage", "linux"),
        }
        if args.build_only:
            print(f"Built VPX {version}: " + ", ".join(str(path) for path in sources.values()))
            return 0
        if not args.dry_run and shutil.which("gh") is None:
            raise ValueError("GitHub CLI (gh) is required; install it and run gh auth login")
        with tempfile.TemporaryDirectory(prefix="vpx-release-") as directory:
            staging = Path(directory)
            assets = []
            checksums = []
            for platform, source in sources.items():
                asset = staging / ASSETS[platform]
                shutil.copy2(source, asset)
                assets.append(asset)
                checksums.append(f"{sha256(asset)}  {asset.name}")
                print(f"{platform}: {source} -> {asset.name}", flush=True)
            checksum_file = staging / "SHA256SUMS.txt"
            checksum_file.write_text("\n".join(checksums) + "\n", encoding="utf-8")
            assets.append(checksum_file)
            notes_file = staging / "release-notes.md"
            notes_file.write_text(notes, encoding="utf-8")
            command = [
                "gh", "release", "create", f"v{version}",
                *[str(asset) for asset in assets],
                "--repo", args.repo, *(["--target", commit] if commit else ["--verify-tag"]), "--title", f"VPX {version}",
                "--notes-file", str(notes_file),
            ]
            if args.draft:
                command.append("--draft")
            if semver.group(4):
                command.append("--prerelease")
            command.append("--latest=false" if args.draft or semver.group(4) else "--latest")
            if args.dry_run:
                print(f"\nPreview only. Remote tag v{version} must already exist.")
                print(shlex.join(command))
                print(f"\nRelease notes:\n{notes}")
                print("Checksums:\n" + "\n".join(checksums))
            else:
                subprocess.run(command, check=True)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
