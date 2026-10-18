#!/usr/bin/env python3
import hashlib
import os
import shutil
import struct
import sys
import zlib

MAGIC = b"VPXPACK1"
ID_SIZE = 40


def main():
    launcher, payload_dir, output = sys.argv[1:4]
    files = sorted(
        os.path.relpath(os.path.join(folder, name), payload_dir)
        for folder, _, names in os.walk(payload_dir)
        for name in names
    )
    digest = hashlib.sha1()
    temporary = output + ".part"
    shutil.copyfile(launcher, temporary)
    with open(temporary, "ab") as out:
        offset = out.tell()
        for relative in files:
            with open(os.path.join(payload_dir, relative), "rb") as source:
                data = source.read()
            packed = zlib.compress(data, 9)
            name = relative.replace(os.sep, "/").encode()
            digest.update(name)
            digest.update(data)
            out.write(struct.pack("<H", len(name)) + name + struct.pack("<QQ", len(data), len(packed)))
            out.write(packed)
            print(f"  {relative:<60} {len(data) / 1e6:8.1f} MB -> {len(packed) / 1e6:6.1f} MB")
        out.write(struct.pack("<H", 0))
        size = out.tell() - offset
        identifier = digest.hexdigest().encode().ljust(ID_SIZE, b" ")
        out.write(MAGIC + struct.pack("<QQ", offset, size) + identifier)
    os.chmod(temporary, 0o755)
    os.replace(temporary, output)


if __name__ == "__main__":
    main()
