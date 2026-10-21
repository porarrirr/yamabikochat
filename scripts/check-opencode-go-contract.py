#!/usr/bin/env python3
"""Check current Go endpoints through the same catalog registration used by iOS."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_URL = "https://raw.githubusercontent.com/anomalyco/opencode/dev/services/www/src/docs/content/console/go.mdx"

def load_url(url):
    return subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "30",
                           "-A", "Mozilla/5.0 YamabikoChat-contract-check", url], check=True, capture_output=True, text=True).stdout

def official_routes(document):
    packages = {"@ai-sdk/openai": "openai-responses", "@ai-sdk/openai-compatible": "openai-completions",
                "@ai-sdk/anthropic": "anthropic-messages", "@ai-sdk/google": "google-generative-ai"}
    routes = {}
    for line in document.splitlines():
        if not line.startswith("|") or "https://opencode.ai/inference/go/" not in line: continue
        cells = [cell.strip().strip("`") for cell in line.strip().strip("|").split("|")]
        if len(cells) >= 4:
            routes[cells[1]] = {"api": packages[cells[3]], "endpoint": cells[2]}
    assert routes, "No current OpenCode Go endpoints found"
    return routes

def main():
    expected = official_routes(load_url(CONTRACT_URL))
    catalog = json.loads(load_url("https://models.dev/catalog.json"))["providers"]["opencode-go"]
    configs = []
    for model_id, route in expected.items():
        model = catalog["models"][model_id]
        provider = model.get("provider", {})
        configs.append({"provider": "opencode-go", "model": model_id, "catalogContract": {
            "providerName": catalog["name"], "npm": provider.get("npm", catalog["npm"]),
            "api": provider.get("api", catalog.get("api")), "shape": provider.get("shape"),
            "provenance": "model" if provider else "provider", "name": model["name"],
            "reasoning": model.get("reasoning"), "toolCall": model.get("tool_call"),
            "input": model["modalities"]["input"], "contextWindow": model["limit"]["context"],
            "maxTokens": model["limit"]["output"]}, "expected": route})
    script = """
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { builtinModels } from '@earendil-works/pi-ai/providers/all';
import { installCatalogProviderAdapters, verifiedCatalogResolution } from './src/catalog-provider-contracts.js';
const models = builtinModels(); installCatalogProviderAdapters(models);
for (const config of JSON.parse(fs.readFileSync(0, 'utf8'))) {
  const r = verifiedCatalogResolution(config, models);
  assert.equal(r?.supported, true, config.model);
  assert.equal(r.api, config.expected.api, config.model);
  const m = models.getModel(r.provider, r.model);
  const endpoint = r.api === 'anthropic-messages' ? `${m.baseUrl}/v1/messages`
    : r.api === 'openai-responses' ? `${m.baseUrl}/responses`
    : r.api === 'openai-completions' ? `${m.baseUrl}/chat/completions`
    : `${m.baseUrl}/models/${m.id}`;
  assert.equal(endpoint, config.expected.endpoint, config.model);
}
"""
    subprocess.run(["node", "--input-type=module", "-e", script], input=json.dumps(configs), cwd=ROOT / "ios/PiRuntime", text=True, check=True)
    # Both Swift catalog decoding and the native gateway preserve the model contract.
    native = (ROOT / "ios/YamabikoChat/Data/Repositories/ProviderGateway.swift").read_text()
    for field in ("npm", "api", "shape"):
        assert f"{field}: model.providerContract?.{field}" in native, f"Native {field} mapping drift"
    print(f"OpenCode Go current official endpoints match Pi and native catalog forwarding ({len(configs)} models)")

if __name__ == "__main__": main()
