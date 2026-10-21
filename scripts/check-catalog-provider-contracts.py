#!/usr/bin/env python3
"""Drift checks for the explicit official catalog contracts registered on Pi."""
import importlib.util
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("go_contract", ROOT / "scripts/check-opencode-go-contract.py")
go = importlib.util.module_from_spec(spec)
spec.loader.exec_module(go)

models = go.load_url("https://raw.githubusercontent.com/anomalyco/opencode/dev/services/www/src/docs/content/console/models.mdx")
for endpoint in ("/inference/openai/v1/responses", "/inference/openai/v1/chat/completions", "/inference/anthropic/v1/messages", "/inference/google/v1beta/models/"):
    assert endpoint in models, f"OpenCode endpoint drift: {endpoint}"
assert "mistral-large-4" in models and "@ai-sdk/openai-compatible" in models, "OpenCode Mistral route drift"
cn = go.load_url("https://platform.minimaxi.com/docs/api-reference/text-chat-anthropic")
assert "https://api.minimax.cn/anthropic/v1/messages" in cn, "MiniMax CN endpoint drift"
zai = go.load_url("https://zcode.z.ai/en/docs/configuration")
for endpoint in ("https://api.z.ai/api/paas/v4", "https://api.z.ai/api/coding/paas/v4"):
    assert endpoint in zai, f"Z.AI endpoint drift: {endpoint}"
mantle = go.load_url("https://docs.aws.amazon.com/bedrock/latest/userguide/inference-chat-completions.html")
for value in ("bedrock-mantle", "/openai/v1", "Amazon Bedrock API key"):
    assert value in mantle, f"Bedrock Mantle contract drift: {value}"
# Check every affected catalog identity against Pi's actual auth resolution, using
# inert test values. No authenticated provider requests leave this checker.
catalog = json.loads(go.load_url("https://models.dev/catalog.json"))["providers"]
script = """
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { builtinModels } from '@earendil-works/pi-ai/providers/all';
import { catalogProviderEnvironment, PROVIDER_ENV_ALIASES } from './src/catalog-provider-contracts.js';
const catalog = JSON.parse(fs.readFileSync(0, 'utf8'));
for (const [provider, aliases] of Object.entries(PROVIDER_ENV_ALIASES)) {
  assert.ok(catalog[provider], provider);
  for (const [target, source] of Object.entries(aliases)) {
    assert.ok(catalog[provider].env.includes(source), `${provider}/${source} catalog env drift`);
    assert.equal(catalogProviderEnvironment(provider, {[source]: 'test'})[target], 'test');
  }
}
"""
subprocess.run(["node", "--input-type=module", "-e", script], input=json.dumps(catalog), cwd=ROOT / "ios/PiRuntime", text=True, check=True)
print("Official provider endpoint contracts and catalog credential aliases match")
