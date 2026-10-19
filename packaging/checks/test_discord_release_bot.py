import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError


SPEC = importlib.util.spec_from_file_location("release_bot", Path(__file__).resolve().parents[1] / "discord" / "release_bot.py")
bot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bot)


def release(number, body="### Fixed\n\n- Playback recovery."):
    return {
        "id": number,
        "tag_name": f"v1.0.{number}",
        "published_at": f"2026-10-{number:02d}T00:00:00Z",
        "draft": False,
        "prerelease": False,
        "html_url": f"https://github.com/gicstin/VPX/releases/tag/v1.0.{number}",
        "body": body,
        "assets": [{"state": "uploaded", "name": "VPX-windows-x86_64.exe", "browser_download_url": "https://github.com/gicstin/VPX/releases/download/v1.0.1/VPX-windows-x86_64.exe"}],
    }


class ReleaseBotTests(unittest.TestCase):
    def test_message_includes_notes_and_downloads_without_truncation(self):
        item = release(1, "### Fixed\n\n" + "- Audio 🎵 recovery.\n" * 400)
        messages = bot.release_messages(item)
        text = "".join(messages)
        self.assertIn(item["body"].strip(), text)
        self.assertIn(item["assets"][0]["browser_download_url"], text)
        self.assertIn(item["html_url"], text)
        self.assertGreater(len(messages), 1)
        self.assertTrue(all(len(message.encode("utf-16-le")) // 2 <= 2000 for message in messages))

    def test_missing_notes_and_assets_use_release_page(self):
        item = release(1, None)
        item["assets"] = []
        text = "".join(bot.release_messages(item))
        self.assertIn("See release page", text)
        self.assertIn(item["html_url"], text)

    @patch.object(bot, "request_json")
    def test_published_release_posts_notes_downloads_and_suppresses_mentions(self, request):
        webhook = "https://discord.com/api/webhooks/123/test-token"
        item = release(1, "@everyone " + "🎵" * 2500)
        bot.announce_release({"action": "published", "release": item}, webhook)
        self.assertGreater(request.call_count, 1)
        for call in request.call_args_list:
            self.assertEqual(call.args, (webhook + "?wait=true",))
            self.assertEqual(call.kwargs["payload"]["allowed_mentions"], {"parse": []})
        self.assertIn(item["body"].strip(), "".join(call.kwargs["payload"]["content"] for call in request.call_args_list))

    @patch.object(bot, "request_json")
    def test_drafts_prereleases_and_other_events_never_post(self, request):
        for action in ("created", "edited", "deleted", "unpublished"):
            bot.announce_release({"action": action, "release": release(1)})
        for field in ("draft", "prerelease"):
            item = release(1)
            item[field] = True
            bot.announce_release({"action": "published", "release": item})
        request.assert_not_called()

    @patch.object(bot, "request_json")
    def test_invalid_event_and_missing_webhook_never_post(self, request):
        for event in ({"action": "published"}, {"action": "published", "release": {}}, {"action": "published", "release": release(1)}):
            with self.assertRaises(ValueError):
                bot.announce_release(event)
        request.assert_not_called()

    @patch.object(bot.time, "sleep")
    @patch.object(bot, "urlopen")
    def test_rate_limit_retries_identical_request(self, urlopen, sleep):
        error = HTTPError("https://discord.com/api/v10/channels/123/messages", 429, "limited", {}, io.BytesIO(b'{"retry_after": 2.5}'))
        response = io.BytesIO(b'{"id": "42"}')
        urlopen.side_effect = [error, response]
        result = bot.request_json(error.url, "Bot secret", {"content": "test", "nonce": "123"})
        self.assertEqual(result, {"id": "42"})
        sleep.assert_called_once_with(2.5)
        self.assertEqual(urlopen.call_args_list[0].args[0].data, urlopen.call_args_list[1].args[0].data)

    @patch.object(bot, "request_json")
    def test_event_file_preview_uses_no_credentials_or_posts(self, request):
        with tempfile.TemporaryDirectory() as directory:
            event = Path(directory) / "event.json"
            event.write_text(json.dumps({"action": "published", "release": release(1)}))
            with patch("sys.stdout", new_callable=io.StringIO) as output:
                self.assertEqual(bot.main(["--dry-run", "--event", str(event)]), 0)
            self.assertIn("v1.0.1", output.getvalue())
        request.assert_not_called()

    @patch.object(bot, "request_json")
    def test_github_event_environment_posts_only_event_release(self, request):
        with tempfile.TemporaryDirectory() as directory:
            event = Path(directory) / "event.json"
            event.write_text(json.dumps({"action": "published", "release": release(2)}))
            with patch.dict("os.environ", {"GITHUB_EVENT_PATH": str(event), "DISCORD_WEBHOOK_URL": "https://discord.com/api/webhooks/123/test-token"}):
                self.assertEqual(bot.main([]), 0)
            self.assertEqual(request.call_count, 1)
            self.assertIn("v1.0.2", request.call_args.kwargs["payload"]["content"])

    @patch.object(bot.time, "sleep")
    @patch.object(bot, "urlopen")
    def test_webhook_credentials_never_appear_in_errors(self, urlopen, sleep):
        url = "https://discord.com/api/webhooks/123/private-token"
        urlopen.side_effect = HTTPError(url, 401, "unauthorized", {}, io.BytesIO(b"{}"))
        with self.assertRaises(bot.APIError) as caught:
            bot.request_json(url, payload={"content": "test"})
        self.assertNotIn("private-token", str(caught.exception))
        urlopen.side_effect = OSError("offline")
        with self.assertRaises(bot.APIError) as caught:
            bot.request_json(url, payload={"content": "test"})
        self.assertNotIn("private-token", str(caught.exception))

    def test_webhook_validation(self):
        self.assertEqual(bot.webhook_id("https://discord.com/api/webhooks/123/test-token"), "123")
        for url in ["http://discord.com/api/webhooks/123/token", "https://example.com/api/webhooks/123/token", "https://discord.com/api/webhooks/123/token?wait=false"]:
            with self.assertRaises(ValueError):
                bot.webhook_id(url)


if __name__ == "__main__":
    unittest.main()
