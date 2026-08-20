#!/usr/bin/env python3
"""Fail when YamabikoChat's OpenCode Go routes drift from the official contract."""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_URL = (
    "https://raw.githubusercontent.com/anomalyco/opencode/"
    "dev/packages/web/src/content/docs/go.mdx"
)
MODELS_DEV_URL = "https://models.dev/api.json"
SWIFT_CATALOG = ROOT / "ios/YamabikoChat/Shared/OpenCodeGoModelCatalog.swift"
KOTLIN_CATALOG = (
    ROOT
    / "app/src/main/java/com/porarri/yamabikochat/data/remote/ProviderCatalog.kt"
)
PI_RUNTIME = ROOT / "ios/PiRuntime/src/main.js"

ENDPOINT_TO_ROUTE = {
    "chat/completions": "chatCompletions",
    "responses": "responses",
    "messages": "messages",
}
NPM_TO_ROUTE = {
    "@ai-sdk/openai-compatible": "chatCompletions",
    "@ai-sdk/openai": "responses",
    "@ai-sdk/anthropic": "messages",
}
PI_API_TO_ROUTE = {
    "openai-completions": "chatCompletions",
    "openai-responses": "responses",
    "anthropic-messages": "messages",
}
SHAPE_TO_ROUTE = {
    "completions": "chatCompletions",
    "responses": "responses",
    "messages": "messages",
}


def official_routes(document: str) -> dict[str, str]:
    routes: dict[str, str] = {}
    for line in document.splitlines():
        if not line.startswith("|") or "https://opencode.ai/zen/go/v1/" not in line:
            continue
        cells = [cell.strip().strip("`") for cell in line.strip().strip("|").split("|")]
        if len(cells) < 4:
            continue
        model_id = cells[1]
        endpoint = cells[2].rstrip("/").rsplit("/", 1)[-1]
        if endpoint == "completions" and cells[2].rstrip("/").endswith("chat/completions"):
            endpoint = "chat/completions"
        route = ENDPOINT_TO_ROUTE.get(endpoint)
        if route is None:
            raise ValueError(f"Unsupported official endpoint for {model_id}: {cells[2]}")
        routes[model_id] = route
    if not routes:
        raise ValueError("No OpenCode Go endpoint rows were found in the official documentation")
    return routes


def swift_routes(source: str) -> dict[str, str]:
    return dict(
        re.findall(
            r'OpenCodeGoModel\(id: "([^"]+)", displayName: "[^"]+", '
            r'endpointKind: \.([A-Za-z]+)',
            source,
        )
    )


def kotlin_routes(source: str) -> dict[str, str]:
    raw = dict(
        re.findall(
            r'OpenCodeGoModel\("([^"]+)", "[^"]+", '
            r'OpenCodeGoEndpointKind\.([A-Z_]+)\)',
            source,
        )
    )
    names = {
        "CHAT_COMPLETIONS": "chatCompletions",
        "RESPONSES": "responses",
        "MESSAGES": "messages",
    }
    return {model_id: names[route] for model_id, route in raw.items()}


def pi_routes(source: str) -> dict[str, str]:
    routes = {}
    for model_id, api in re.findall(
        r'\{ id: "([^"]+)", api: "([^"]+)" \}',
        source,
    ):
        route = PI_API_TO_ROUTE.get(api)
        if route is None:
            raise ValueError(f"Unsupported Pi API for {model_id}: {api}")
        routes[model_id] = route
    if not routes:
        raise ValueError("No verified OpenCode Go routes were found in Pi Runtime")
    return routes


def models_dev_routes(document: dict) -> dict[str, str]:
    provider = document["opencode-go"]
    default_npm = provider["npm"]
    routes = {}
    for model_id, model in provider["models"].items():
        contract = model.get("provider") or {}
        shape = contract.get("shape")
        if shape in SHAPE_TO_ROUTE:
            routes[model_id] = SHAPE_TO_ROUTE[shape]
            continue
        npm = contract.get("npm", default_npm)
        route = NPM_TO_ROUTE.get(npm)
        if route is not None:
            routes[model_id] = route
    return routes


def describe_diff(expected: dict[str, str], actual: dict[str, str]) -> list[str]:
    problems: list[str] = []
    missing = sorted(expected.keys() - actual.keys())
    extra = sorted(actual.keys() - expected.keys())
    changed = sorted(
        model_id
        for model_id in expected.keys() & actual.keys()
        if expected[model_id] != actual[model_id]
    )
    if missing:
        problems.append(f"missing models: {', '.join(missing)}")
    if extra:
        problems.append(f"models absent from official contract: {', '.join(extra)}")
    for model_id in changed:
        problems.append(
            f"wrong route for {model_id}: expected {expected[model_id]}, got {actual[model_id]}"
        )
    return problems


def load_url(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "YamabikoChat-contract-check"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def main() -> int:
    try:
        expected = official_routes(load_url(CONTRACT_URL).decode("utf-8"))
    except Exception as error:
        print(f"Unable to load the official OpenCode Go contract: {error}", file=sys.stderr)
        return 2
    try:
        catalog_routes = models_dev_routes(json.loads(load_url(MODELS_DEV_URL)))
    except Exception as error:
        print(f"Unable to load the models.dev OpenCode Go catalog: {error}", file=sys.stderr)
        return 2

    platforms = {
        "iOS": swift_routes(SWIFT_CATALOG.read_text()),
        "Android": kotlin_routes(KOTLIN_CATALOG.read_text()),
        "Pi": pi_routes(PI_RUNTIME.read_text()),
    }
    failed = False
    for platform, actual in platforms.items():
        problems = describe_diff(expected, actual)
        if problems:
            failed = True
            print(f"{platform} OpenCode Go catalog is out of date:", file=sys.stderr)
            for problem in problems:
                print(f"  - {problem}", file=sys.stderr)
    if failed:
        return 1

    catalog_problems = describe_diff(
        expected,
        {model_id: route for model_id, route in catalog_routes.items() if model_id in expected},
    )
    for problem in catalog_problems:
        print(
            f"::warning title=models.dev OpenCode Go contract drift::{problem}",
            file=sys.stderr,
        )

    print(f"OpenCode Go contract verified for {len(expected)} models on iOS, Android, and Pi.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
