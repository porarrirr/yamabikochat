import { AsyncLocalStorage } from "node:async_hooks";

// Transport policy around Pi's normal SDK transport. Never follow a redirect
// with credentials or retry through a different URL/provider/protocol.
export function credentialFetch(fetcher) {
  return async (input, options = {}) => {
    const url = new URL(typeof input === "string" || input instanceof URL ? input : input.url);
    if (!secureEndpoint(url)) throw Object.assign(new Error("HTTPS is required for provider connections"), { code: "insecure_provider_endpoint" });
    const response = await fetcher(input, { ...options, redirect: "error" });
    if (response.redirected || response.status >= 300 && response.status < 400) {
      throw Object.assign(new Error("Provider redirects are disabled"), { code: "provider_redirect_rejected" });
    }
    return response;
  };
}

export function secureEndpoint(url) {
  if (url.username || url.password) return false;
  return url.protocol === "https:" || url.protocol === "http:" && ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
}

const contexts = new AsyncLocalStorage();
const sensitive = /^(?:api[_-]?key|access(?:[_-]?token)?|refresh(?:[_-]?token)?|id[_-]?token|client[_-]?secret|password|secret|(?:mcp)?authorization(?:[_-]?token)?|credential)$/i;

export class CredentialRedactor {
  #values = new Set();
  observe(value, key = "") {
    if (typeof value === "string" && sensitive.test(key) && value.length >= 4) {
      this.#values.add(value);
      this.#values.add(encodeURIComponent(value));
    } else if (value && typeof value === "object") {
      for (const [name, nested] of Object.entries(value)) {
        if (name === "env" || name === "headers") {
          for (const [field, secret] of Object.entries(nested || {})) {
            if (/key|token|secret|password|authorization|credential/i.test(field) && typeof secret === "string" && secret.length >= 4) {
              this.#values.add(secret); this.#values.add(encodeURIComponent(secret));
            }
          }
        }
        this.observe(nested, name);
      }
    }
  }
  text(value) {
    let result = String(value ?? "");
    for (const secret of [...this.#values].sort((a, b) => b.length - a.length)) result = result.split(secret).join("[REDACTED]");
    return result
      .replace(/\bbearer\s+[^\s"',;]+/gi, "Bearer [REDACTED]")
      .replace(/(["']?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|authorization[_-]?token|client[_-]?secret|password|secret)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,&}\]]+)/gi, "$1[REDACTED]")
      .replace(/([?&](?:code|state|access_token|refresh_token|id_token|id_token_hint|token|password|secret|api_key|apikey|authorization)=)[^&\s]+/gi, "$1[REDACTED]");
  }
  value(value) {
    const seen = new WeakSet();
    return JSON.parse(JSON.stringify(value, (key, nested) => {
      if (sensitive.test(key) || /^(?:mcpAuthorizationToken|x-api-key|x-goog-api-key)$/i.test(key)) return "[REDACTED]";
      if (key === "signal" || key === "abortSignal" || typeof nested === "function") return undefined;
      if (typeof nested === "string") return this.text(nested);
      if (nested && typeof nested === "object") { if (seen.has(nested)) return "[CIRCULAR]"; seen.add(nested); }
      return nested;
    }));
  }
}

const fallback = new CredentialRedactor();
export const diagnosticRedactor = () => contexts.getStore() || fallback;
export const withCredentialSecurity = operation => contexts.run(new CredentialRedactor(), operation);
