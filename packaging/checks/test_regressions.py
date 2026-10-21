import http.server
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]


def jump_ogg_timestamps(data):
    pages = bytearray(data)
    offset = 0
    while offset < len(pages):
        header_size = 27 + pages[offset + 26]
        page_size = header_size + sum(pages[offset + 27:offset + header_size])
        granule = int.from_bytes(pages[offset + 6:offset + 14], "little")
        if 44100 < granule < 2**63:
            pages[offset + 6:offset + 14] = (granule + 44100 * 86400 * 32).to_bytes(8, "little")
            pages[offset + 22:offset + 26] = bytes(4)
            checksum = 0
            for value in pages[offset:offset + page_size]:
                checksum ^= value << 24
                for _ in range(8):
                    checksum = ((checksum << 1) ^ (0x04C11DB7 if checksum & 0x80000000 else 0)) & 0xFFFFFFFF
            pages[offset + 22:offset + 26] = checksum.to_bytes(4, "little")
        offset += page_size
    return pages


class MediaServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, media):
        super().__init__(("127.0.0.1", 0), MediaHandler)
        self.media = media
        self.stopped = threading.Event()
        self.release = threading.Event()
        self.requests = 0
        self.delayed_requests = {}
        self.lock = threading.Lock()


class MediaHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def do_HEAD(self):
        if self.path == "/radio-get":
            self.send_error(405)
        elif self.path == "/radio-redirect":
            self.send_response(302)
            self.send_header("Location", "/radio")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path in ["/radio", "/radio-clock"]:
            self.send_response(200)
            self.send_header("Content-Type", "application/ogg")
            self.send_header("Icy-Name", "VPX Test Radio")
            self.end_headers()
        elif self.path == "/radio-page":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
        elif self.path == "/radio-slow":
            self.server.stopped.wait(15)
        else:
            self.send_error(404)

    def do_GET(self):
        try:
            if self.path in ["/art.png", "/slow-art.png", "/other-art.png"]:
                if self.path == "/slow-art.png":
                    self.server.stopped.wait(0.7)
                name = "other.png" if self.path == "/other-art.png" else "photo.png"
                data = (self.server.media / name).read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            if self.path == "/station-metadata":
                second = self.server.release.is_set()
                body = json.dumps({"title": "Second Song" if second else "First Song", "artist": "Station Artist", "album": "Station Album", "cover": f"http://127.0.0.1:{self.server.server_port}/other-art.png" if second else f"http://127.0.0.1:{self.server.server_port}/art.png"}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if self.path == "/radio-icy":
                self.send_response(200)
                self.send_header("Content-Type", "audio/mpeg")
                self.send_header("icy-name", "VPX Metadata Radio")
                self.send_header("icy-metaint", "4096")
                self.send_header("Connection", "close")
                self.end_headers()
                data = (self.server.media / "radio.mp3").read_bytes()
                for index, offset in enumerate(range(0, len(data), 4096)):
                    if index == 16:
                        self.server.release.wait(15)
                    chunk = data[offset:offset + 4096]
                    self.wfile.write(chunk)
                    if len(chunk) == 4096:
                        second = index >= 16
                        title = "Second Artist - Second Song" if second else "First Artist - First Song"
                        art = "other-art.png" if second else "art.png"
                        metadata = f"StreamTitle='{title}';StreamUrl='http://127.0.0.1:{self.server.server_port}/{art}';".encode()
                        blocks = (len(metadata) + 15) // 16
                        self.wfile.write(bytes([blocks]) + metadata.ljust(blocks * 16, b"\0"))
                    self.wfile.flush()
                self.server.stopped.wait(20)
                return
            if self.path in ["/radio", "/radio-get", "/radio-clock", "/radio-jitter", "/radio-opus"]:
                self.send_response(200)
                self.send_header("Content-Type", "application/ogg")
                self.send_header("Icy-Name", "VPX Test Radio")
                self.send_header("Connection", "close")
                self.end_headers()
                name = {"/radio-clock": "radio-clock.ogg", "/radio-opus": "radio-opus.ogg"}.get(self.path, "radio.ogg")
                data = (self.server.media / name).read_bytes()
                if self.path == "/radio-jitter":
                    offset = 0
                    while offset < len(data):
                        header_size = 27 + data[offset + 26]
                        page_size = header_size + sum(data[offset + 27:offset + header_size])
                        granule = int.from_bytes(data[offset + 6:offset + 14], "little")
                        offset += page_size
                        if granule >= 44100 * 4:
                            break
                    self.wfile.write(data[:offset])
                    self.wfile.flush()
                    self.server.release.wait(15)
                    data = data[offset:]
                self.wfile.write(data)
                self.wfile.flush()
                self.server.stopped.wait(20)
                return
            if self.path == "/release":
                self.server.release.set()
                self.send_response(200)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.path.startswith("/delayed"):
                with self.server.lock:
                    first = self.path not in self.server.delayed_requests
                    self.server.delayed_requests[self.path] = True
                delay = (2.0 if "slow" in self.path else 0.5) if first else 0.0
                if self.server.stopped.wait(delay):
                    return
                filename = "movie.mp4" if self.path.endswith(".mp4") else "audio.wav"
                data = (self.server.media / filename).read_bytes()
                total = len(data)
                offset = int(self.headers.get("Range", "bytes=0-").split("=")[1].split("-")[0])
                self.send_response(206 if "Range" in self.headers else 200)
                self.send_header("Accept-Ranges", "bytes")
                if "Range" in self.headers:
                    self.send_header("Content-Range", f"bytes {offset}-{total - 1}/{total}")
                self.send_header("Content-Length", str(total - offset))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data[offset:])
                return
            if self.path == "/release-local":
                self.server.release.set()
                self.send_response(200)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.path.startswith("/never"):
                self.server.stopped.wait(20)
                return
            if self.path != "/audio.wav?token=kept" or self.headers.get("X-VPX-Test") != "yes":
                self.send_error(403)
                return
            with self.server.lock:
                self.server.requests += 1
                first = self.server.requests == 1
            data = (self.server.media / "audio.wav").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Connection", "close")
            self.end_headers()
            if first:
                initial = 48000 * 2 * 8 + 128
                self.wfile.write(data[:initial])
                self.wfile.flush()
                while not self.server.stopped.is_set():
                    if self.server.release.wait(0.05):
                        self.wfile.write(data[initial:])
                        self.wfile.flush()
                        break
                self.server.stopped.wait(10)
            else:
                self.wfile.write(data)
                self.wfile.flush()
                self.server.stopped.wait(10)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass


class RegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.godot = shutil.which(os.environ.get("GODOT", "godot"))
        if not cls.godot or not shutil.which("ffmpeg"):
            raise unittest.SkipTest("Godot and FFmpeg required")
        cls.temporary = tempfile.TemporaryDirectory(prefix="vpx-regressions-")
        cls.directory = Path(cls.temporary.name)
        cls.media = cls.directory / "media"
        cls.media.mkdir()
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "90", "-c:a", "pcm_s16le", str(cls.media / "audio.wav")], check=True, timeout=20)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "1", str(cls.media / "short.wav")], check=True, timeout=20)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "45", "-c:a", "flac", "-f", "ogg", str(cls.media / "radio.ogg")], check=True, timeout=20)
        (cls.media / "radio-clock.ogg").write_bytes(jump_ogg_timestamps((cls.media / "radio.ogg").read_bytes()))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "10", "-c:a", "libopus", "-frame_duration", "2.5", str(cls.media / "radio-opus.ogg")], check=True, timeout=20)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "45", "-c:a", "libmp3lame", "-b:a", "128k", "-write_xing", "0", str(cls.media / "radio.mp3")], check=True, timeout=20)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=160x90:r=10", "-t", "12", "-c:v", "mpeg4", "-g", "1", "-movflags", "+faststart", str(cls.media / "movie.mp4")], check=True, timeout=20)
        (cls.media / "movie.en.srt").write_text("1\n00:00:00,000 --> 00:00:10,000\nFilesystem subtitle\n")
        for filename, color in [("photo.png", "blue"), ("other.png", "green")]:
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"color=c={color}:s=160x90", "-frames:v", "1", str(cls.media / filename)], check=True, timeout=20)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_case(self, mode):
        server = MediaServer(self.media)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        feeder = None
        if mode in ["local_cancel", "local_read"]:
            pipe = self.media / "blocked.wav"
            os.mkfifo(pipe)
            def release_pipe():
                if mode == "local_cancel":
                    server.release.wait(20)
                while not server.stopped.is_set():
                    try:
                        descriptor = os.open(pipe, os.O_WRONLY | os.O_NONBLOCK)
                    except OSError:
                        time.sleep(0.01)
                        continue
                    if mode == "local_read":
                        data = (self.media / "audio.wav").read_bytes()[:48000 * 2 * 8 + 128]
                        try:
                            while data and not server.stopped.is_set():
                                try:
                                    count = os.write(descriptor, data)
                                    data = data[count:]
                                except BlockingIOError:
                                    time.sleep(0.01)
                            server.release.wait(20)
                            os.write(descriptor, b"\0" * 1024)
                        except BrokenPipeError:
                            pass
                    os.close(descriptor)
                    return
            feeder = threading.Thread(target=release_pipe, daemon=True)
            feeder.start()
        environment = dict(os.environ, XDG_DATA_HOME=str(self.directory / mode))
        for name in ["VPX_DECODE", "VPX_DECODE_SETTING", "VPX_MODE_SESSION", "VPX_WANT_XR"]:
            environment.pop(name, None)
        script = f"{mode}.gd" if mode in ["interaction_safety", "keyboard_input"] else "regressions.gd"
        command = [self.godot, "--headless", "--path", str(ROOT), "--xr-mode", "off", "--audio-driver", "Dummy", "--script", str(ROOT / "packaging/checks" / script), "--", mode, f"http://127.0.0.1:{server.server_port}", str(self.media), "--desktop"]
        if mode == "core":
            command.extend(["--decode", "sw"])
        output_path = self.directory / f"{mode}.log"
        try:
            with output_path.open("w+") as log:
                process = subprocess.Popen(command, env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    process.wait(timeout=35)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                    log.seek(0)
                    self.fail(f"{mode} hung\n{log.read()}")
                log.seek(0)
                output = log.read()
            self.assertEqual(process.returncode, 0, output)
            self.assertNotIn("SCRIPT ERROR", output, output)
            self.assertNotIn("FAIL:", output, output)
            self.assertIn(f"RESULT: {mode}", output, output)
            self.assertIn("failures=0", output, output)
            print(next(line for line in output.splitlines() if line.startswith("RESULT:")), flush=True)
        finally:
            server.stopped.set()
            server.release.set()
            server.shutdown()
            server.server_close()
            worker.join(timeout=1)
            if feeder is not None:
                feeder.join(timeout=1)
                pipe.unlink(missing_ok=True)

    def test_interaction_safety(self):
        self.run_case("interaction_safety")

    def test_keyboard_input(self):
        self.run_case("keyboard_input")

    def test_remote_open_transport(self):
        self.run_case("remote_open")

    def test_online_radio(self):
        self.run_case("online_radio")

    def test_online_source_navigation(self):
        self.run_case("online_navigation")

    def test_radio_audio_clock(self):
        self.run_case("radio_clock")

    def test_radio_buffering(self):
        self.run_case("radio_jitter")

    def test_radio_short_audio_frames(self):
        self.run_case("radio_opus")

    def test_link_history_and_clicks(self):
        self.run_case("link_history")

    def test_radio_metadata(self):
        self.run_case("radio_metadata")

    def test_finishing_track_during_replacement(self):
        self.run_case("replacement_end")

    @unittest.skipUnless(hasattr(os, "mkfifo"), "POSIX pipe required")
    def test_cancel_blocked_filesystem_open(self):
        self.run_case("local_cancel")

    @unittest.skipUnless(hasattr(os, "mkfifo"), "POSIX pipe required")
    def test_replace_blocked_filesystem_playback(self):
        self.run_case("local_read")

    def test_remote_playlist_and_decoder(self):
        self.run_case("core")

    def test_music_retry_after_photo_navigation(self):
        self.run_case("music_retry")

    def test_music_retry_after_cancelled_replacement(self):
        self.run_case("music_cancel")

    def test_music_retry_after_failed_photo(self):
        self.run_case("music_failed_photo")

    def test_music_transient_stall_after_photo_navigation(self):
        self.run_case("music_transient")


if __name__ == "__main__":
    unittest.main()
