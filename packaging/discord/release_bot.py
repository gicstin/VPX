import argparse
import json
import logging
import os
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


LOG = logging.getLogger("vpx.discord")


class APIError(RuntimeError):
    pass


def request_json(url, token=None, payload=None):
    endpoint = "Discord webhook" if "/webhooks/" in url else url
    headers = {"User-Agent": "VPX-Release-Bot/1.0", "Accept": "application/json"}
    if token:
        headers["Authorization"] = token
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    for attempt in range(5):
        try:
            with urlopen(Request(url, data=data, headers=headers), timeout=30) as response:
                return json.load(response)
        except HTTPError as error:
            if error.code == 429:
                try:
                    delay = float(json.load(error).get("retry_after", 1))
                except (ValueError, TypeError):
                    delay = 1
                time.sleep(max(1, delay))
            elif error.code >= 500:
                time.sleep(2 ** attempt)
            else:
                raise APIError(f"{endpoint}: HTTP {error.code}; check credentials, channel permissions and repository access") from None
        except (URLError, TimeoutError, OSError):
            time.sleep(2 ** attempt)
    raise APIError(f"{endpoint}: request failed after five attempts")


def webhook_id(url):
    match = re.fullmatch(r"https://discord\.com/api(?:/v10)?/webhooks/(\d{1,20})/[A-Za-z0-9_-]+", url)
    if not match:
        raise ValueError("DISCORD_WEBHOOK_URL must be a Discord webhook URL without query parameters")
    return match[1]


def split_content(text, limit=1900):
    chunks = []
    while text:
        end = min(len(text), limit)
        while len(text[:end].encode("utf-16-le")) // 2 > limit:
            end -= 1
        if end < len(text):
            newline = text.rfind("\n", 0, end)
            if newline > end // 2:
                end = newline + 1
        chunks.append(text[:end])
        text = text[end:]
    return chunks


def release_messages(release):
    tag = release["tag_name"]
    lines = [f"# VPX {tag} available", "", f"Release: <{release['html_url']}>", "", "**Downloads**"]
    assets = [asset for asset in release.get("assets", []) if asset.get("state") == "uploaded"]
    if assets:
        lines.extend(f"{asset['name']}: <{asset['browser_download_url']}>" for asset in assets)
    else:
        lines.append(f"<{release['html_url']}>")
    lines.extend(["", "**Changelog since previous version**", "", (release.get("body") or "See release page for changes.").strip()])
    return split_content("\n".join(lines))


def announce_release(event, webhook=None, dry_run=False):
    if event.get("action") != "published":
        LOG.info("Skipping event: release is not being published")
        return
    release = event.get("release")
    if not isinstance(release, dict):
        raise ValueError("event must contain a release object")
    if release.get("draft") or release.get("prerelease"):
        LOG.info("Skipping draft or prerelease")
        return
    for field in ("tag_name", "html_url"):
        if not isinstance(release.get(field), str) or not release[field]:
            raise ValueError(f"release is missing {field}")
    if not dry_run:
        if not webhook:
            raise ValueError("set DISCORD_WEBHOOK_URL")
        webhook_id(webhook)
    messages = release_messages(release)
    for index, message in enumerate(messages):
        if dry_run:
            print(message, end="\n\n")
        else:
            request_json(f"{webhook}?wait=true", payload={
                "content": message,
                "allowed_mentions": {"parse": []},
            })
            LOG.info("Posted %s part %d/%d", release["tag_name"], index + 1, len(messages))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Announce a published GitHub release in Discord. Python 3.10+, no dependencies.")
    parser.add_argument("--event", type=Path, default=os.environ.get("GITHUB_EVENT_PATH"), help="GitHub release event JSON; defaults to GITHUB_EVENT_PATH")
    parser.add_argument("--dry-run", action="store_true", help="preview without posting or credentials")
    args = parser.parse_args(argv)
    if not args.event:
        parser.error("pass --event or set GITHUB_EVENT_PATH")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        event = json.loads(args.event.read_text(encoding="utf-8"))
        if not isinstance(event, dict):
            raise ValueError("event must be a JSON object")
        announce_release(event, os.environ.get("DISCORD_WEBHOOK_URL"), args.dry_run)
    except (APIError, OSError, ValueError) as error:
        LOG.error("%s", error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
