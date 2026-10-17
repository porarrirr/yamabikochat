#!/usr/bin/env python3
"""Fail on changes to the official Sarashina fields used by Pi; never infer new routes."""
import re
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip = False
    def handle_starttag(self, tag, attrs):
        if tag in ("style", "script"): self.skip = True
    def handle_endtag(self, tag):
        if tag in ("style", "script"): self.skip = False
    def handle_data(self, data):
        if not self.skip: self.parts.append(data)

def page(path):
    request = urllib.request.Request("https://docs.sarashina.ai/" + path, headers={"User-Agent": "YamabikoChat-contract-check"})
    with urllib.request.urlopen(request, timeout=20) as response:
        parser = Text()
        parser.feed(response.read().decode())
        return "".join(parser.parts)

chat, models = page("api-reference/chat-completions"), page("models")
assert "https://api.sarashina.ai/v1/chat/completions" in chat, "Sarashina endpoint drift"
assert re.search(r"max_completion_tokens.*?1から8000", chat, re.S), "Sarashina output limit drift"
assert re.search(r"stream_options.*?サポートしていません", chat, re.S), "Sarashina stream_options support drift"
assert '"system", "user", "assistant", "tool"' in chat, "Sarashina message role drift"
assert "非長考モデル" in models, "Sarashina reasoning contract drift"
for model in ("sarashina3-mini", "sarashina3-nano", "sarashina3-guard"):
    assert model in chat, f"Sarashina model removed: {model}"
assert re.search(r"Sarashina3 mini.*?128k", models, re.S)
assert re.search(r"Sarashina3 nano.*?128k", models, re.S)
assert re.search(r"Sarashina3 guard.*?64k", models, re.S)
root = Path(__file__).resolve().parents[1]
for path in ("ios/YamabikoChat/Shared/ProviderDisplay.swift",):
    assert "sarashina3-mini" in (root / path).read_text(), f"Sarashina native mapping missing: {path}"
print("Sarashina official contract matches Pi and native mappings")
