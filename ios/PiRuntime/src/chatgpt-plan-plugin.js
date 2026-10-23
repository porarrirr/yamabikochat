// Sign in with ChatGPT provider extension. Inference stays in Pi's Responses
// adapter; this module owns only the published SIWC OAuth/catalog contract.
// https://developers.openai.com/siwc/token-sharing-open-source/sign-in
import { createHash, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { createLocalJWKSet, jwtVerify } from "jose";
import { createProvider, getSupportedThinkingLevels } from "@earendil-works/pi-ai";
import { openaiProvider } from "@earendil-works/pi-ai/providers/openai";
import { openAIResponsesApi } from "@earendil-works/pi-ai/api/openai-responses.lazy";
import { safeOAuthCode } from "./auth-security.js";

export const CHATGPT_PLAN_PROVIDER = "openai-chatgpt";
export const CHATGPT_USAGE_URL = "https://chatgpt.com/settings/usage";
const ISSUER = "https://auth.openai.com";
const RESOURCE = "https://api.openai.com/v1";
const DYNAMIC_CLIENT = "dynamic_agent_client";
const PLAN_SCOPE = "chatgpt.tokens.use.direct";
const SCOPES = `openid profile email offline_access resource.invoke ${PLAN_SCOPE}`;
const UUID_URI = /^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CONTRACT_EFFORT_VALUES = new Set(["none", "minimal", "low", "medium", "high", "xhigh", "max"]);
const CONTRACT_LEVEL_KEYS = ["minimal", "low", "medium", "high", "xhigh", "max"];

function failure(code, message) { return Object.assign(new Error(message), { code }); }
function required(value, name) {
  if (typeof value !== "string" || !value.trim()) throw failure("chatgpt_contract_invalid", `ChatGPT ${name} is missing`);
  return value;
}
function issuedClient(value) {
  const id = required(value, "issued client ID");
  if (id === DYNAMIC_CLIENT) throw failure("chatgpt_registration_incomplete", "ChatGPT did not issue a client ID");
  return id;
}
function authURL(value) {
  const url = new URL(required(value, "discovery endpoint"));
  if (url.origin !== ISSUER || url.username || url.password || url.hash) {
    throw failure("chatgpt_discovery_invalid", "Unexpected ChatGPT discovery endpoint");
  }
  return url.toString();
}

function earliestRefreshMs(value) {
  if (value === undefined) return 0;
  const milliseconds = typeof value === "number" ? value * 1000 : typeof value === "string" ? Date.parse(value) : NaN;
  if (!Number.isFinite(milliseconds) || milliseconds < 0) throw failure("chatgpt_contract_invalid", "Invalid ChatGPT earliest refresh time");
  return milliseconds;
}

export function chatGPTPlanCompleted(message) {
  return message?.rawStopReason === "completed" && !message.errorMessage &&
    ["stop", "toolUse"].includes(message.stopReason);
}

export function parseChatGPTCallback(url, pending) {
  if (url.pathname !== "/auth/callback") throw failure("chatgpt_callback_invalid", "Unexpected callback path");
  if (url.searchParams.get("state") !== pending.state) throw failure("chatgpt_state_mismatch", "ChatGPT OAuth state mismatch");
  const error = url.searchParams.get("error");
  if (error) throw failure(error, error === "access_denied" ? "ChatGPTへの接続が許可されませんでした。" : `ChatGPT authorization failed (${error})`);
  const code = required(url.searchParams.get("code"), "authorization code");
  const returnedClient = url.searchParams.get("client_id");
  if (pending.clientId && returnedClient && returnedClient !== pending.clientId) {
    throw failure("chatgpt_client_mismatch", "ChatGPT callback changed the selected account registration");
  }
  return { code, clientId: issuedClient(returnedClient || pending.clientId) };
}

// Static and self-contained: never render callback values or load external assets.
const CHATGPT_CALLBACK_HTML = `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="color-scheme" content="dark">
  <meta name="referrer" content="no-referrer">
  <title>ChatGPTの認証完了 · YamabikoChat</title>
  <style>
    :root { color-scheme: dark; --navy: #131A34; --gray: #F5F5F5; --lime: #ADFF00; }
    * { box-sizing: border-box; }
    body { margin: 0; padding: max(24px, env(safe-area-inset-top)) max(24px, env(safe-area-inset-right)) max(24px, env(safe-area-inset-bottom)) max(24px, env(safe-area-inset-left)); background: var(--navy); color: var(--gray); font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; -webkit-font-smoothing: antialiased; }
    .shell { max-width: 440px; margin: 0 auto; }
    header { display: flex; align-items: center; gap: 10px; font-size: 18px; font-weight: 650; }
    header svg { width: 28px; height: 28px; flex-shrink: 0; color: var(--lime); }
    main { padding-top: 40px; }
    .success { display: grid; place-items: center; width: 48px; height: 48px; margin-bottom: 20px; border-radius: 50%; background: rgb(173 255 0 / 12%); color: var(--lime); }
    .success svg { width: 28px; height: 28px; }
    h1 { margin: 0; font-size: 28px; line-height: 1.5; letter-spacing: -.6px; }
    .instruction { margin: 20px 0 16px; font-size: 17px; line-height: 1.8; }
    .return-link { display: flex; align-items: center; justify-content: center; gap: 12px; width: 100%; min-height: 72px; padding: 18px 16px; border: 2px solid var(--lime); border-radius: 14px; background: var(--lime); color: var(--navy); font-size: 20px; font-weight: 700; text-align: center; text-decoration: none; line-height: 1.5; box-shadow: 0 4px 0 #6b9e00; }
    .return-link svg { width: 24px; height: 24px; flex-shrink: 0; }
    .return-link:hover { background: #c5ff4d; border-color: #c5ff4d; }
    .return-link:focus-visible { outline: 3px solid var(--gray); outline-offset: 6px; }
    .return-link:active { transform: translateY(2px); box-shadow: 0 2px 0 #6b9e00; }
    .hint { margin: 12px 0 0; color: #c4c9d8; font-size: 14px; line-height: 1.7; text-align: center; }
    .fallback { margin: 32px 0 0; padding-top: 20px; border-top: 1px solid rgb(245 245 245 / 20%); color: #c4c9d8; font-size: 14px; line-height: 1.8; }
    .fallback strong { display: block; margin-bottom: 6px; color: var(--gray); font-weight: 600; }
    @media (max-width: 350px) {
      body { padding-left: 20px; padding-right: 20px; }
      main { padding-top: 28px; }
      h1 { font-size: 25px; }
      .return-link { font-size: 18px; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header>
      <svg viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="m3 25 10-18 5 9 3-5 8 14H3Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="m9 14 4 3 4-3" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>
      YamabikoChat
    </header>
    <main aria-labelledby="title">
      <div class="success" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="m5 12 4 4L19 6" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
      <h1 id="title">ChatGPTの認証が<br>完了しました</h1>
      <!-- APP_RETURN_LINK -->
    </main>
  </div>
</body>
</html>`;

function chatGPTCallbackHTML(userAgent = "") {
  // iPad Safari can identify as Macintosh. Android has no registered app scheme.
  const supportsAppReturn = /iPhone|iPad|iPod|Macintosh/.test(userAgent);
  // This fixed link only foregrounds iOS; credentials still resolve through Pi.
  return CHATGPT_CALLBACK_HTML.replace("<!-- APP_RETURN_LINK -->", supportsAppReturn
    ? `<p class="instruction">下のボタンをタップして、<br>アプリに戻ってください。</p>
      <a class="return-link" href="yamabikochat://auth/complete">YamabikoChatに戻る<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M5 12h14m-6-6 6 6-6 6" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg></a>
      <p class="hint">「開く」と表示されたら、そのまま進んでください。</p>
      <p class="fallback"><strong>ボタンで戻れない場合</strong>画面左上の「◀ YamabikoChat」、またはアプリ切り替えで戻れます。</p>`
    : '<p class="instruction">YamabikoChatに戻って、接続状態を確認してください。</p>');
}

// Listener failure is a hard failure. There is no pasted-code or alternate flow.
export async function startChatGPTCallback(pending, signal, port = 0) {
  signal.throwIfAborted();
  let resolveResult, rejectResult;
  const result = new Promise((resolve, reject) => { resolveResult = resolve; rejectResult = reject; });
  // A disconnect can abort before the caller attaches to result.
  result.catch(() => {});
  let consumed = false;
  const server = createServer((request, response) => {
    const url = new URL(request.url || "", "http://127.0.0.1");
    if (request.method !== "GET" || url.pathname !== "/auth/callback") {
      response.writeHead(404); response.end(); return;
    }
    if (consumed) { response.writeHead(409); response.end(); return; }
    try {
      const callback = parseChatGPTCallback(url, pending);
      consumed = true;
      response.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
      response.end(chatGPTCallbackHTML(request.headers["user-agent"]));
      resolveResult(callback);
    } catch (error) {
      response.writeHead(400, { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" });
      response.end("ChatGPT callback rejected. Return to YamabikoChat.");
      // Unrelated/malformed callbacks must not terminate an active login.
      if (url.searchParams.get("state") === pending.state) { consumed = true; rejectResult(error); }
    }
  });
  const close = () => { server.close(); server.closeAllConnections(); };
  const abort = () => { rejectResult(signal.reason); close(); };
  signal.addEventListener("abort", abort, { once: true });
  try {
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(port, "127.0.0.1", () => { server.off("error", reject); resolve(); });
    });
    signal.throwIfAborted();
    server.on("error", rejectResult);
    return {
      redirectURI: `http://127.0.0.1:${server.address().port}/auth/callback`,
      result,
      close() { signal.removeEventListener("abort", abort); close(); }
    };
  } catch (error) { signal.removeEventListener("abort", abort); close(); throw error; }
}

export function chatGPTRegistration(credential) {
  if (!credential || credential.contract !== "siwc-v1") throw failure("chatgpt_reconnect_required", "公式のChatGPT連携でログインし直してください。");
  return {
    clientId: issuedClient(credential.clientId), hostId: required(credential.hostId, "host ID"),
    issuer: required(credential.issuer, "issuer"), subject: required(credential.subject, "subject"),
    email: credential.email ?? null
  };
}

// models.dev is the authoritative supplement for account slugs that the bundled
// Pi release does not ship as built-ins. The contract must resolve
// unambiguously to Pi's Responses adapter on the public OpenAI endpoint;
// anything else fails closed with a typed reason and stays listed but disabled.
function catalogContractModel(id, name, contract) {
  if (!contract || typeof contract !== "object" || !["provider", "model"].includes(contract.provenance)) {
    return { reason: "catalog_contract_incomplete" };
  }
  if (contract.shape !== undefined && contract.shape !== null) {
    if (contract.shape !== "responses") return { reason: "protocol_conflict" };
    if (contract.npm !== undefined && contract.npm !== null && contract.npm !== "@ai-sdk/openai") {
      return { reason: "protocol_conflict" };
    }
  } else if (contract.npm !== "@ai-sdk/openai") {
    return { reason: "protocol_conflict" };
  }
  if (contract.api !== undefined && contract.api !== null) {
    const api = typeof contract.api === "string" ? contract.api.trim().replace(/\/+$/, "") : null;
    if (api !== RESOURCE) return { reason: "endpoint_conflict" };
  }
  const input = Array.isArray(contract.input) ? contract.input.filter(value => typeof value === "string") : [];
  const contextWindow = Number(contract.contextWindow);
  const maxTokens = Number(contract.maxTokens);
  if (!input.includes("text") || !Number.isInteger(contextWindow) || contextWindow <= 0 ||
      !Number.isInteger(maxTokens) || maxTokens <= 0 || typeof contract.reasoning !== "boolean") {
    return { reason: "catalog_contract_incomplete" };
  }
  const efforts = !contract.reasoning ? [] : (Array.isArray(contract.reasoningEfforts) ? contract.reasoningEfforts : [])
    .map(value => typeof value === "string" ? value.trim().toLowerCase() : "");
  if (contract.reasoning && (!efforts.length || efforts.some(value => !CONTRACT_EFFORT_VALUES.has(value)))) {
    return { reason: "catalog_contract_incomplete" };
  }
  const model = {
    id, name, api: "openai-responses", provider: CHATGPT_PLAN_PROVIDER, baseUrl: RESOURCE,
    reasoning: contract.reasoning,
    input: input.filter(value => ["text", "image"].includes(value)),
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow, maxTokens
  };
  if (contract.reasoning) {
    model.thinkingLevelMap = { off: efforts.includes("none") ? "none" : null };
    for (const level of CONTRACT_LEVEL_KEYS) model.thinkingLevelMap[level] = efforts.includes(level) ? level : null;
  }
  return { model };
}

export function createChatGPTPlanPlugin({
  fetch: fetcher = globalThis.fetch,
  callbackListener = startChatGPTCallback,
  now = Date.now
} = {}) {
  let loginContext = null;
  let accountCatalog = [];
  let catalogClientId = null;
  let catalogGeneration = 0;
  let catalogRequestClient = null;
  // Metadata comes from exact Pi built-ins first; models.dev contracts supplement
  // account slugs that Pi does not ship. Unknown account models stay disabled.
  const builtin = new Map(openaiProvider().getModels().map(model => [model.id, model]));
  const contractCache = new Map();
  let discoveryCache = null;
  let keysCache = null;
  async function readJSON(url, signal, options = {}) {
    const response = await fetcher(url, { ...options, signal, redirect: "error" });
    if (!response.ok) {
      let code = "chatgpt_request_failed";
      try { const body = await response.json(); code = body.error?.code || body.error || code; } catch {}
      throw Object.assign(failure(safeOAuthCode(code), `ChatGPT request failed (${response.status})`), { statusCode: response.status });
    }
    try { return await response.json(); }
    catch { throw failure("chatgpt_response_invalid", "ChatGPT returned an invalid authentication response"); }
  }
  async function discovery(signal) {
    if (discoveryCache && now() < discoveryCache.expires) return discoveryCache.value;
    const value = await readJSON(`${ISSUER}/.well-known/openid-configuration`, signal);
    if (value.issuer !== ISSUER) throw failure("chatgpt_issuer_mismatch", "Unexpected ChatGPT issuer");
    for (const field of ["authorization_endpoint", "token_endpoint", "jwks_uri", "revocation_endpoint"]) authURL(value[field]);
    discoveryCache = { value, expires: now() + 300_000 };
    return value;
  }
  async function verifyIdentity(token, clientId, nonce, signal) {
    const config = await discovery(signal);
    // Cache issuer keys briefly; refetch once on an unfamiliar kid for key rotation.
    if (!keysCache || now() >= keysCache.expires) {
      keysCache = { keys: await readJSON(config.jwks_uri, signal), expires: now() + 300_000 };
    }
    let verified;
    const options = { issuer: ISSUER, audience: clientId, requiredClaims: ["sub", "exp", "iat"], clockTolerance: 5, currentDate: new Date(now()) };
    try { verified = await jwtVerify(required(token, "ID token"), createLocalJWKSet(keysCache.keys), options); }
    catch (error) {
      if (error.code !== "ERR_JWKS_NO_MATCHING_KEY") throw failure("chatgpt_identity_invalid", "ChatGPT ID token verification failed");
      keysCache = { keys: await readJSON(config.jwks_uri, signal), expires: now() + 300_000 };
      try { verified = await jwtVerify(token, createLocalJWKSet(keysCache.keys), options); }
      catch { throw failure("chatgpt_identity_invalid", "ChatGPT ID token verification failed"); }
    }
    const identity = verified.payload;
    if (nonce !== undefined && identity.nonce !== nonce) throw failure("chatgpt_nonce_mismatch", "ChatGPT ID token nonce mismatch");
    required(identity.sub, "identity subject");
    if (Array.isArray(identity.aud) && identity.aud.length > 1 && identity.azp !== clientId) throw failure("chatgpt_identity_invalid", "ChatGPT authorized party mismatch");
    return identity;
  }
  function credentialFrom(token, registration, identity, previous) {
    required(token.access_token, "access token"); required(token.refresh_token, "refresh token");
    if (token.token_type?.toLowerCase() !== "bearer" || !Number.isFinite(token.expires_in) || token.expires_in <= 0) {
      throw failure("chatgpt_contract_invalid", "Invalid ChatGPT token response");
    }
    const scopes = required(token.scope, "granted scopes").split(/\s+/);
    const accessExpiresAt = now() + token.expires_in * 1000;
    const earliest = earliestRefreshMs(token.earliest_refresh_at);
    return {
      type: "oauth", contract: "siwc-v1", access: token.access_token, refresh: token.refresh_token,
      expires: Math.min(accessExpiresAt, Math.max(accessExpiresAt - 180_000, earliest)),
      accessExpiresAt,
      ...(token.earliest_refresh_at !== undefined ? { earliestRefreshAt: token.earliest_refresh_at } : {}),
      clientId: registration.clientId,
      hostId: registration.hostId, issuer: ISSUER, subject: identity.sub,
      email: typeof identity.email === "string" ? identity.email : previous?.email ?? null,
      idToken: token.id_token ?? previous?.idToken, scopes
    };
  }
  async function tokenRequest(params, signal) {
    const config = await discovery(signal);
    return readJSON(config.token_endpoint, signal, {
      method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body: new URLSearchParams({ ...params, resource: RESOURCE })
    });
  }
  const oauth = {
    name: "ChatGPT plan", loginLabel: "Continue with ChatGPT", isSubscription: true,
    async login(interaction) {
      const context = loginContext;
      if (!context || !UUID_URI.test(context.hostId)) throw failure("chatgpt_host_invalid", "ChatGPT requires a persistent installation UUID");
      const previous = context.registration;
      if (previous && (previous.hostId !== context.hostId || previous.issuer && previous.issuer !== ISSUER)) throw failure("chatgpt_registration_invalid", "ChatGPT registration does not belong to this installation");
      const state = randomBytes(32).toString("base64url");
      const nonce = randomBytes(32).toString("base64url");
      const verifier = randomBytes(64).toString("base64url");
      const signal = AbortSignal.any([interaction.signal, AbortSignal.timeout(10 * 60_000)]);
      const config = await discovery(signal);
      const callback = await callbackListener({ state, clientId: previous?.clientId }, signal);
      try {
        const url = new URL(config.authorization_endpoint);
        url.search = new URLSearchParams({
          client_id: previous ? issuedClient(previous.clientId) : DYNAMIC_CLIENT,
          ext_agent_host_id: context.hostId, response_type: "code", redirect_uri: callback.redirectURI,
          resource: RESOURCE, scope: SCOPES, state, nonce, code_challenge_method: "S256",
          code_challenge: createHash("sha256").update(verifier).digest("base64url"),
          ...(!previous ? { agent_name_hint: "YamabikoChat" } : {}),
          ...(previous?.idToken ? { id_token_hint: previous.idToken } : {}),
          ...(previous?.email ? { login_hint: previous.email } : {})
        }).toString();
        interaction.notify({ type: "auth_url", url: url.toString(), instructions: "ChatGPTにログインし、このアプリでのプラン利用を許可してください。" });
        const result = await callback.result;
        // Persist before exchange so an expired/failed code never loses registration.
        await context.onRegistration({
          clientId: result.clientId, hostId: context.hostId,
          ...(previous?.subject ? { issuer: previous.issuer, subject: previous.subject, email: previous.email ?? null } : {})
        });
        const token = await tokenRequest({ grant_type: "authorization_code", client_id: result.clientId, code: result.code, code_verifier: verifier, redirect_uri: callback.redirectURI }, signal);
        const identity = await verifyIdentity(token.id_token, result.clientId, nonce, signal);
        if (previous?.subject && identity.sub !== previous.subject) throw failure("chatgpt_account_mismatch", "ChatGPT sign-in returned another account");
        return credentialFrom(token, { clientId: result.clientId, hostId: context.hostId }, identity);
      } finally { callback.close(); }
    },
    async refresh(credential, signal) {
      const registration = chatGPTRegistration(credential);
      const earliest = earliestRefreshMs(credential.earliestRefreshAt);
      if (now() < earliest) {
        if (!Number.isFinite(credential.accessExpiresAt) || now() >= credential.accessExpiresAt) {
          throw failure("chatgpt_refresh_not_yet_allowed", "ChatGPT access token expired before its permitted refresh time");
        }
        return { ...credential, expires: Math.min(credential.accessExpiresAt, earliest) };
      }
      const token = await tokenRequest({ grant_type: "refresh_token", client_id: registration.clientId, refresh_token: credential.refresh }, signal);
      let identity = { sub: registration.subject, email: credential.email };
      if (token.id_token) {
        identity = await verifyIdentity(token.id_token, registration.clientId, undefined, signal);
        if (identity.sub !== registration.subject) throw failure("chatgpt_account_mismatch", "ChatGPT refresh returned another account");
      }
      return credentialFrom(token, registration, identity, credential);
    },
    async toAuth(credential) {
      chatGPTRegistration(credential);
      if (!credential.scopes?.includes(PLAN_SCOPE)) throw failure("chatgpt_plan_permission_required", "ChatGPTプランの利用が許可されていません。ChatGPTで利用を許可してください。");
      return { apiKey: credential.access };
    }
  };
  const provider = createProvider({
    id: CHATGPT_PLAN_PROVIDER, name: "ChatGPT plan", baseUrl: RESOURCE,
    auth: { oauth }, models: [], api: openAIResponsesApi()
  });
  // getModels exposes only the account's authorized catalog, using exact Pi
  // metadata or a verified models.dev contract for slugs Pi does not ship.
  const registeredProvider = { ...provider, getModels: () => accountCatalog.filter(entry => entry.model).map(entry => entry.model) };
  return {
    provider: registeredProvider,
    async withLoginContext(context, operation) {
      if (loginContext) throw failure("chatgpt_login_busy", "ChatGPT login is already running");
      loginContext = context;
      try { return await operation(); } finally { loginContext = null; }
    },
    profile(credential) {
      const registration = chatGPTRegistration(credential);
      return { email: credential.email ?? null, planType: null, accountId: registration.clientId, planUsageEnabled: credential.scopes?.includes(PLAN_SCOPE) === true };
    },
    clearCatalog() { catalogGeneration++; catalogRequestClient = null; accountCatalog = []; catalogClientId = null; contractCache.clear(); },
    modelStatus(id) {
      const entry = accountCatalog.find(entry => entry.id === id);
      return entry ? entry.reason : catalogClientId ? "chatgpt_model_unavailable" : "chatgpt_catalog_required";
    },
    modelSource(id) {
      return accountCatalog.find(entry => entry.id === id)?.source ?? null;
    },
    async catalog(credential, signal, contracts = {}) {
      const registration = chatGPTRegistration(credential);
      await oauth.toAuth(credential);
      if (contracts && typeof contracts === "object") {
        for (const [slug, contract] of Object.entries(contracts)) {
          if (slug) contractCache.set(slug, contract);
        }
      }
      // Clear first: a failed fetch must never expose another account's catalog.
      const generation = catalogRequestClient === registration.clientId ? catalogGeneration : ++catalogGeneration;
      catalogRequestClient = registration.clientId;
      accountCatalog = []; catalogClientId = null;
      const response = await readJSON(`${RESOURCE}/models`, signal, { headers: { authorization: `Bearer ${credential.access}` } });
      if (!Array.isArray(response.models)) throw failure("chatgpt_catalog_invalid", "ChatGPT model response must contain models");
      const seen = new Set();
      const catalog = response.models.filter(entry => entry.visibility === "list").map(entry => {
        const id = required(entry.slug, "model slug"), name = required(entry.display_name, "model display name");
        if (seen.has(id)) throw failure("chatgpt_catalog_invalid", "ChatGPT catalog contains duplicate models");
        seen.add(id);
        const original = builtin.get(id);
        if (original && original.api === "openai-responses") {
          return { id, name, model: { ...original, name, provider: CHATGPT_PLAN_PROVIDER, baseUrl: RESOURCE }, reason: null, source: "pi_builtin" };
        }
        if (contractCache.has(id)) {
          const resolved = catalogContractModel(id, name, contractCache.get(id));
          return { id, name, model: resolved.model ?? null, reason: resolved.reason ?? null, source: resolved.model ? "models_dev_contract" : null };
        }
        return { id, name, model: null, reason: "pi_model_missing", source: null };
      });
      if (generation !== catalogGeneration) throw failure("chatgpt_catalog_superseded", "ChatGPT account catalog changed during discovery");
      accountCatalog = catalog;
      catalogClientId = registration.clientId;
      return accountCatalog.map(({ id, name, model, reason, source }) => ({
        id, name, supported: !!model, reason, source,
        supportedThinkingLevels: model?.reasoning ? getSupportedThinkingLevels(model).filter(level => level !== "off") : []
      }));
    },
    async revoke(credential, signal) {
      const registration = chatGPTRegistration(credential);
      const config = await discovery(signal);
      for (let attempt = 0; ; attempt++) {
        let response;
        try {
          response = await fetcher(config.revocation_endpoint, {
            method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({ token: credential.refresh, token_type_hint: "refresh_token", client_id: registration.clientId }),
            signal, redirect: "error"
          });
        } catch (error) {
          if (attempt >= 2 || signal.aborted) throw error;
        }
        if (response?.status === 200) return;
        if (response && (response.status < 500 || attempt >= 2)) throw failure("chatgpt_revocation_failed", `ChatGPT revocation failed (${response.status})`);
        // Documented session-revocation retry uses the same endpoint and token.
        await new Promise((resolve, reject) => {
          const aborted = () => { clearTimeout(timer); reject(signal.reason); };
          const timer = setTimeout(() => { signal.removeEventListener("abort", aborted); resolve(); }, 250 * 2 ** attempt);
          signal.addEventListener("abort", aborted, { once: true });
          if (signal.aborted) aborted();
        });
      }
    }
  };
}

// Use Pi's onPayload hook for the documented preview contract. This does not
// implement a stream or tool loop. Unsupported requested tools fail explicitly.
export function chatGPTPlanPayload(payload) {
  const value = { ...payload, store: false, stream: true };
  // Pi's one-off summaries request cacheRetention: "none", which API-key
  // models serialize as prompt_cache_options: { mode: "explicit" }. SIWC
  // rejects that optional control (HTTP 400, observed with gpt-6-luna).
  // Keep this route-specific restriction here, without changing Pi's models.
  delete value.prompt_cache_options;
  for (const field of ["background", "conversation", "max_output_tokens", "max_tool_calls", "metadata", "moderation", "multi_agent", "prompt", "prompt_cache_retention", "safety_identifier", "temperature", "top_logprobs", "top_p", "truncation", "user", "previous_response_id"]) delete value[field];
  if (!Array.isArray(value.input)) throw failure("chatgpt_input_invalid", "ChatGPT plan requires an input array");
  value.input = value.input.map(item => item.role === "system" ? { ...item, role: "developer" } : item);
  const tools = value.tools || [];
  for (const tool of tools) {
    if (!["function", "custom", "namespace", "web_search", "web_search_preview"].includes(tool.type)) throw failure("chatgpt_tool_unsupported", `ChatGPT plan does not support ${tool.type}`);
  }
  const local = tools.filter(tool => tool.type === "function" || tool.type === "custom");
  if (local.length) value.tools = [...tools.filter(tool => !local.includes(tool)), { type: "namespace", name: "yamabiko", description: "YamabikoChat local tools", tools: local }];
  return value;
}
