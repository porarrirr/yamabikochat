#!/usr/bin/env python3
"""Check the authoritative xAI discovery contract used by the pinned Pi OAuth provider."""
import json
from urllib.request import Request, urlopen

ISSUER = "https://auth.x.ai"
with urlopen(Request(ISSUER + "/.well-known/openid-configuration", headers={"User-Agent": "YamabikoChat-contract-check"}), timeout=30) as response:
    metadata = json.load(response)
assert metadata["issuer"] == ISSUER
for field, route in {
    "authorization_endpoint": "/oauth2/authorize",
    "token_endpoint": "/oauth2/token",
    "revocation_endpoint": "/oauth2/revoke",
    "jwks_uri": "/.well-known/jwks.json",
}.items():
    assert metadata[field] == ISSUER + route, f"xAI OAuth contract drift: {field}"
assert "none" in metadata["token_endpoint_auth_methods_supported"]
assert "S256" in metadata["code_challenge_methods_supported"]
assert "refresh_token" in metadata["grant_types_supported"]
print("Official xAI OAuth issuer, public-client, PKCE and revocation metadata match the Pi provider")
