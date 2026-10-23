
// YamabikoChat security extension to the existing pi-grok OAuth provider.
// RFC 7009, using only xAI's live authoritative OIDC revocation endpoint.
export async function revoke(
    credentials: import("@earendil-works/pi-ai").OAuthCredentials,
    signal: AbortSignal = AbortSignal.timeout(20_000),
): Promise<void> {
    const discovery = await discover();
    if (!discovery.revocation_endpoint) {
        throw Object.assign(new Error("xAI does not advertise token revocation"), { code: "xai_revocation_unsupported" });
    }
    const endpoint = validateEndpoint(discovery.revocation_endpoint, "revocation_endpoint");
    for (const [token, hint] of [[credentials.refresh, "refresh_token"], [credentials.access, "access_token"]]) {
        if (!token) continue;
        signal.throwIfAborted();
        const response = await safeFetch(endpoint, {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({ token, token_type_hint: hint, client_id: CLIENT_ID }),
            signal,
        });
        if (response.status !== 200) {
            throw Object.assign(new Error("xAI token revocation was not confirmed"), { code: "xai_revocation_failed" });
        }
        await response.body?.cancel();
    }
}
