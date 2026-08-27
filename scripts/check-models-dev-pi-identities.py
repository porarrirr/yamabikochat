#!/usr/bin/env python3
"""Verify the minimal models.dev-to-Pi identity exceptions against upstream."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PI_RUNTIME = ROOT / "ios/PiRuntime/src/main.js"
MODELS_DEV_URL = "https://models.dev/api.json"


def load_models_dev() -> dict:
    request = urllib.request.Request(
        MODELS_DEV_URL,
        headers={"User-Agent": "YamabikoChat-provider-contract-check"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def configured_exceptions(source: str) -> dict[str, str]:
    block = re.search(
        r"const PROVIDER_IDENTITY_EXCEPTIONS = new Map\(\[(.*?)\]\);",
        source,
        re.DOTALL,
    )
    if not block:
        raise ValueError("Pi provider identity exception table was not found")
    return dict(re.findall(r'\["([^"]+)",\s*"([^"]+)"\]', block.group(1)))


def pi_models() -> dict[str, set[str]]:
    script = """
import { builtinProviders } from './node_modules/@earendil-works/pi-ai/dist/providers/all.js';
console.log(JSON.stringify(Object.fromEntries(
  builtinProviders().map((provider) => [provider.id, provider.getModels().map((model) => model.id)])
)));
"""
    output = subprocess.check_output(
        ["node", "--input-type=module", "-e", script],
        cwd=ROOT / "ios/PiRuntime",
        text=True,
    )
    return {provider: set(models) for provider, models in json.loads(output).items()}


def main() -> int:
    try:
        catalog = load_models_dev()
        identities = configured_exceptions(PI_RUNTIME.read_text())
        providers = pi_models()
    except Exception as error:
        print(f"Unable to verify provider identities: {error}", file=sys.stderr)
        return 2

    failures: list[str] = []
    for catalog_id, pi_id in identities.items():
        if catalog_id not in catalog:
            failures.append(f"models.dev provider disappeared: {catalog_id}")
            continue
        if pi_id not in providers:
            failures.append(f"Pi provider disappeared: {pi_id} (for {catalog_id})")
            continue
        catalog_models = set(catalog[catalog_id].get("models", {}))
        shared_models = catalog_models & providers[pi_id]
        if not shared_models:
            failures.append(
                f"provider identity has no exact shared models: {catalog_id} -> {pi_id}"
            )

    if failures:
        print("models.dev/Pi provider identity drift detected:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"Verified {len(identities)} irreducible models.dev/Pi identity exceptions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
