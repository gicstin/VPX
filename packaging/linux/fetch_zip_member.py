#!/usr/bin/env python3
import io
import shutil
import sys
import urllib.request
import zipfile

BLOCK = 1 << 20


class HttpRangeFile(io.RawIOBase):
    def __init__(self, url):
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request) as response:
            self.url = response.geturl()
            self.size = int(response.headers["Content-Length"])
        self.position = 0
        self.blocks = {}

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        base = {io.SEEK_SET: 0, io.SEEK_CUR: self.position, io.SEEK_END: self.size}[whence]
        self.position = max(0, base + offset)
        return self.position

    def _block(self, index):
        if index not in self.blocks:
            start = index * BLOCK
            end = min(self.size, start + BLOCK) - 1
            request = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{end}"})
            with urllib.request.urlopen(request) as response:
                self.blocks[index] = response.read()
        return self.blocks[index]

    def read(self, count=-1):
        if count is None or count < 0:
            count = self.size - self.position
        count = min(count, self.size - self.position)
        chunks = []
        while count > 0:
            index, offset = divmod(self.position, BLOCK)
            data = self._block(index)[offset:offset + count]
            chunks.append(data)
            self.position += len(data)
            count -= len(data)
            if len(self.blocks) > 8:
                self.blocks.pop(next(iter(self.blocks)))
        return b"".join(chunks)

    def readinto(self, buffer):
        data = self.read(len(buffer))
        buffer[:len(data)] = data
        return len(data)


def main():
    url, member, destination = sys.argv[1:4]
    with zipfile.ZipFile(HttpRangeFile(url)) as archive:
        with archive.open(member) as source, open(destination, "wb") as target:
            shutil.copyfileobj(source, target, BLOCK)


if __name__ == "__main__":
    main()
