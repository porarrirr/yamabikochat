#!/usr/bin/env python3
"""Check Azure model routes and the missing REST version/auth contract upstream."""
import json
import subprocess
import re
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def fetch(url):
    return subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "30",
         "--user-agent", "Mozilla/5.0 YamabikoChat-contract-check", url],
        check=True, capture_output=True, text=True,
    ).stdout

catalog = json.loads(fetch("https://models.dev/api.json"))["azure"]
fixture = json.loads((ROOT / "ios/PiRuntime/test/fixtures/azure-models.json").read_text())
for model_id, model in fixture.items():
    actual = catalog["models"][model_id]
    assert actual.get("provider") == model["provider"], f"Azure routing drift: {model_id}"
    assert actual["modalities"] == model["modalities"], f"Azure modalities drift: {model_id}"
    assert actual["limit"] == model["limit"], f"Azure limits drift: {model_id}"
    for flag in ("reasoning", "tool_call", "attachment"):
        assert actual.get(flag) == model.get(flag), f"Azure capability drift: {model_id}/{flag}"
responses = fetch("https://learn.microsoft.com/en-us/azure/ai-services/openai/overview")
assert "gpt-chat-latest" in responses and "Responses API" in responses, "Azure GPT Chat Latest route drift"
assert "fixed, nonzero reasoning level" in responses, "Azure GPT Chat Latest reasoning contract drift"
claude = fetch("https://learn.microsoft.com/en-us/azure/foundry/foundry-models/how-to/use-foundry-models-claude")
assert ".services.ai.azure.com/anthropic/v1/messages" in claude, "Azure Messages endpoint drift"
assert "x-api-key:" in claude and "anthropic-version:" in claude, "Azure Messages auth/version drift"
assert "Microsoft Entra ID authentication only" in claude, "Azure Mythos authentication drift"
class TableRows(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows, self.row, self.cell = [], [], None
    def handle_starttag(self, tag, attrs):
        if tag == "tr": self.row = []
        if tag in ("td", "th"): self.cell = ""
    def handle_data(self, data):
        if self.cell is not None: self.cell += data
    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.cell is not None:
            self.row.append(" ".join(self.cell.split()))
            self.cell = None
        if tag == "tr": self.rows.append(self.row)

thinking = TableRows()
thinking.feed(fetch("https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/claude-models"))
rows = {row[0]: row[1:] for row in thinking.rows if len(row) == 4 and row[1] == "Yes"}
source = (ROOT / "ios/PiRuntime/src/azure-provider.js").read_text()
for symbol in ("AZURE_ADAPTIVE_MODELS", "mandatoryThinking"):
    block = re.search(rf"{symbol} = new Set\(\[(.*?)\]\)", source, re.S).group(1)
    for model_id in re.findall(r'"([^"]+)"', block):
        assert model_id in rows, f"Azure adaptive thinking drift: {model_id}"
        if symbol == "mandatoryThinking":
            assert rows[model_id][2] == "No", f"Azure mandatory thinking drift: {model_id}"
inference = fetch("https://learn.microsoft.com/en-us/rest/api/microsoftfoundry/model-inference/get-chat-completions/get-chat-completions?view=rest-microsoftfoundry-model-inference-2024-05-01-preview")
for value in ("2024-05-01-preview", "/chat/completions", "api-key"):
    assert value in inference, f"Azure inference contract drift: {value}"
# Native code passes the exact model-level contract; it never chooses a Pi adapter.
gateway = (ROOT / "ios/YamabikoChat/Data/Repositories/ProviderGateway.swift").read_text()
for value in ("npm: model.providerContract?.npm", "api: model.providerContract?.api", "shape: model.providerContract?.shape"):
    assert value in gateway, f"Native Azure contract forwarding drift: {value}"
print(f"Azure official routing, authentication and version contracts match ({len(fixture)} models)")
