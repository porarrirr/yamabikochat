#!/usr/bin/env python3
"""Fail when OpenAI's SIWC contract drifts from the Pi provider extension."""
from pathlib import Path
import re
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "ios/PiRuntime/src/chatgpt-plan-plugin.js").read_text()
BASE = "https://developers.openai.com/siwc/token-sharing-open-source/"


def page(name):
    with urlopen(Request(BASE + name + ".md", headers={"User-Agent": "YamabikoChat-contract-check"}), timeout=30) as response:
        return response.read().decode()


sign_in = page("sign-in")
inference = page("models-and-inference")
preview = page("preview-limitations")
sessions = page("profiles-and-sessions")
for value in ["dynamic_agent_client", "ext_agent_host_id", "agent_name_hint", "chatgpt.tokens.use.direct", "resource.invoke", "nonce", "client_id"]:
    assert value in sign_in and value in SOURCE, f"SIWC sign-in contract drift: {value}"
for value in ["https://api.openai.com/v1", "store", "stream", "slug", "display_name", "visibility"]:
    assert value in inference and value in SOURCE, f"SIWC inference contract drift: {value}"
for value in ["revocation_endpoint", "token_type_hint", "refresh_token"]:
    assert value in sessions and value in SOURCE, f"SIWC session contract drift: {value}"
upstream_line = next(line for line in preview.splitlines() if "Unsupported fields:" in line)
unsupported = set(re.findall(r"`([a-z_]+)`", upstream_line))
assert unsupported, "SIWC preview field list is missing"
local_line = next(line for line in SOURCE.splitlines() if "for (const field of [" in line and '"background"' in line)
local = set(re.findall(r'"([a-z_]+)"', local_line))
assert local == unsupported | {"previous_response_id"}, f"SIWC preview contract drift: upstream={sorted(unsupported)}, local={sorted(local)}"
assert "previous_response_id" in preview
print("Official ChatGPT plan OAuth, session, catalog and preview contracts match the Pi plugin")
