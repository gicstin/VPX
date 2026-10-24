import argparse
from functools import partial
import http.server
import json
import math
import os
from pathlib import Path
import ssl
import struct
import subprocess
import tempfile
import threading
import wave


PROTOCOLS = {"http", "https", "tls", "ftp", "rtmp", "rtmps", "rtp", "srt", "tcp", "udp"}
DEMUXERS = {"hls", "dash", "rtsp"}


def run(arguments, environment=None):
    result = subprocess.run(arguments, env=environment, capture_output=True, timeout=20)
    if result.returncode:
        raise RuntimeError(f"{arguments[0]} failed: {result.stderr.decode(errors='replace')}")
    return result


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", self.server.secure_url + "/tone.wav")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        super().do_GET()


def check(directory):
    ffmpeg = str((directory / "ffmpeg").resolve())
    ffprobe = str((directory / "ffprobe").resolve())
    for tool in [ffmpeg, ffprobe]:
        protocols = run([tool, "-v", "error", "-protocols"]).stdout.decode().split("Input:", 1)[1].split("Output:", 1)[0].split()
        missing = PROTOCOLS.difference(protocols)
        if missing:
            raise RuntimeError(f"{tool}: missing input protocols: {', '.join(sorted(missing))}")
        demuxers = {name for line in run([tool, "-v", "error", "-demuxers"]).stdout.decode().splitlines()
                    if len(fields := line.split()) >= 2 and fields[0] == "D" for name in fields[1].split(",")}
        missing = DEMUXERS.difference(demuxers)
        if missing:
            raise RuntimeError(f"{tool}: missing demuxers: {', '.join(sorted(missing))}")
    with tempfile.TemporaryDirectory(prefix="vpx-network-") as temporary:
        root = Path(temporary)
        pcm = b"".join(struct.pack("<h", round(12000 * math.sin(2 * math.pi * 440 * i / 48000))) for i in range(48000))
        with wave.open(str(root / "tone.wav"), "wb") as audio:
            audio.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
            audio.writeframes(pcm)
        for muxer, target in [("hls", "stream.m3u8"), ("dash", "stream.mpd")]:
            run([ffmpeg, "-v", "error", "-i", str(root / "tone.wav"), "-c:a", "aac", "-f", muxer, str(root / target)])
        certificate = root / "certificate.pem"
        key = root / "key.pem"
        run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
             "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
             "-keyout", str(key), "-out", str(certificate)])
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certificate, key)
        environment = dict(os.environ, SSL_CERT_FILE=str(certificate))
        handler = partial(Handler, directory=str(root))
        secure = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        plain = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        secure.socket = context.wrap_socket(secure.socket, server_side=True)
        secure_url = f"https://127.0.0.1:{secure.server_port}"
        plain.secure_url = secure.secure_url = secure_url
        workers = [threading.Thread(target=server.serve_forever, daemon=True) for server in [secure, plain]]
        for worker in workers:
            worker.start()
        try:
            cases = [(f"http://127.0.0.1:{plain.server_port}/tone.wav", False),
                     (secure_url + "/tone.wav", True),
                     (f"http://127.0.0.1:{plain.server_port}/redirect", True),
                     (secure_url + "/stream.m3u8", True), (secure_url + "/stream.mpd", True)]
            for url, verify in cases:
                options = ["-rw_timeout", "5000000"]
                if verify:
                    options += ["-tls_verify", "1", "-ca_file", str(certificate)]
                probe = json.loads(run([ffprobe, "-v", "error", *options, "-show_entries", "stream=codec_type", "-of", "json", url], environment).stdout)
                if not any(stream.get("codec_type") == "audio" for stream in probe.get("streams", [])):
                    raise RuntimeError(f"No audio found: {url}")
                decoded = run([ffmpeg, "-v", "error", *options, "-i", url, "-t", "0.5", "-f", "s16le", "-ac", "1", "-ar", "48000", "pipe:1"], environment).stdout
                if len(decoded) < 24000 or not any(decoded):
                    raise RuntimeError(f"Audio decode failed: {url}")
                print(f"PASS: bundled probe and decode {url}", flush=True)
            for tool in [ffmpeg, ffprobe]:
                arguments = [tool, "-v", "error", "-rw_timeout", "5000000", "-tls_verify", "1"]
                arguments += ["-i", secure_url + "/tone.wav", "-f", "null", "-"] if tool == ffmpeg else [secure_url + "/tone.wav"]
                rejected = subprocess.run(arguments, capture_output=True, timeout=10)
                if rejected.returncode == 0 or b"certificate" not in rejected.stderr.lower():
                    raise RuntimeError(f"{tool}: untrusted TLS certificate was not rejected")
                print(f"PASS: {Path(tool).name} rejects untrusted TLS certificates", flush=True)
        finally:
            for server in [secure, plain]:
                server.shutdown()
                server.server_close()
            for worker in workers:
                worker.join(timeout=2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    check(args.directory)
