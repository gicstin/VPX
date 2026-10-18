#!/usr/bin/env python3
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import urllib.request

VERSION = "4.0.0"
SHA256 = "af050313ee63bc18b35b2e064e5dce05b276aaf6d1aa2b8a82ced1fe2f8028e9"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--prefix", type=Path, required=True)
    parser.add_argument("--meson", required=True)
    parser.add_argument("--cross-file", type=Path)
    parser.add_argument("--compat-header", type=Path)
    parser.add_argument("--jobs", default="8")
    args = parser.parse_args()
    stamp = args.prefix / ".rubberband-stamp"
    cross_key = hashlib.sha256(args.cross_file.read_bytes()).hexdigest() if args.cross_file else "native"
    compat_key = hashlib.sha256(args.compat_header.read_bytes()).hexdigest() if args.compat_header else "none"
    key = f"{VERSION} {SHA256} {cross_key} {compat_key}"
    if stamp.exists() and stamp.read_text() == key and (args.prefix / "lib/librubberband.a").exists():
        return
    args.work.mkdir(parents=True, exist_ok=True)
    archive = args.work / f"rubberband-{VERSION}.tar.bz2"
    if not archive.exists():
        with urllib.request.urlopen(f"https://breakfastquay.com/files/releases/rubberband-{VERSION}.tar.bz2", timeout=60) as response:
            archive.write_bytes(response.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise SystemExit("Rubber Band source checksum mismatch")
    source = args.work / f"rubberband-{VERSION}"
    if not source.exists():
        with tarfile.open(archive) as handle:
            handle.extractall(args.work, filter="data")
    build = args.work / ("rubberband-windows" if args.cross_file else "rubberband-linux")
    command = [args.meson, "setup", str(build), str(source), f"--prefix={args.prefix}", "--libdir=lib", "--buildtype=release", "-Ddefault_library=static", "-Dfft=builtin", "-Dresampler=builtin", "-Djni=disabled", "-Dladspa=disabled", "-Dlv2=disabled", "-Dvamp=disabled", "-Dcmdline=disabled", "-Dtests=disabled"]
    if (build / "meson-private").exists():
        command.append("--reconfigure")
    if args.cross_file:
        command += ["--cross-file", str(args.cross_file)]
    if args.compat_header:
        flags = f"-include {args.compat_header}"
        command += [f"-Dc_args={flags}", f"-Dcpp_args={flags}"]
    env = os.environ.copy()
    if args.compat_header:
        for variable in ["CFLAGS", "CXXFLAGS"]:
            env[variable] = env.get(variable, "") + f" -include {args.compat_header}"
    subprocess.run(command, check=True, env=env)
    subprocess.run([args.meson, "compile", "-C", str(build), "-j", args.jobs], check=True, env=env)
    subprocess.run([args.meson, "install", "-C", str(build)], check=True, env=env)
    pc = args.prefix / "lib/pkgconfig/rubberband.pc"
    pc.write_text(pc.read_text() + "\nLibs.private: " + ("-lc++" if args.cross_file else "-lstdc++ -lm") + "\n")
    stamp.write_text(key)


if __name__ == "__main__":
    main()
