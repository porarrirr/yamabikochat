#!/usr/bin/env python3
"""Fail when YamabikoChat's OpenCode Go routes drift from the official contract."""

from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_URL = (
    "https://raw.githubusercontent.com/anomalyco/opencode/"
    "dev/packages/web/src/content/docs/go.mdx"
)
SWIFT_CATALOG = ROOT / "ios/YamabikoChat/Shared/OpenCodeGoModelCatalog.swift"
KOTLIN_CATALOG = (
    ROOT
    / "app/src/main/java/com/porarri/yamabikochat/data/remote/ProviderCatalog.kt"
)

ENDPOINT_TO_ROUTE = {
    "chat/completions": "chatCompletions",
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


def main() -> int:
    try:
        with urllib.request.urlopen(CONTRACT_URL, timeout=30) as response:
            expected = official_routes(response.read().decode("utf-8"))
    except Exception as error:
        print(f"Unable to load the official OpenCode Go contract: {error}", file=sys.stderr)
        return 2

    platforms = {
        "iOS": swift_routes(SWIFT_CATALOG.read_text()),
        "Android": kotlin_routes(KOTLIN_CATALOG.read_text()),
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

    print(f"OpenCode Go contract verified for {len(expected)} models on iOS and Android.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
