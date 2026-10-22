// Sign in with ChatGPT provider extension. Inference stays in Pi's Responses
// adapter; this module owns only the published SIWC OAuth/catalog contract.
// https://developers.openai.com/siwc/token-sharing-open-source/sign-in
import { createHash, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { createLocalJWKSet, jwtVerify } from "jose";
import { createProvider, getSupportedThinkingLevels } from "@earendil-works/pi-ai";
import { openaiProvider } from "@earendil-works/pi-ai/providers/openai";
import { openAIResponsesApi } from "@earendil-works/pi-ai/api/openai-responses.lazy";

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
// Unmodified ChatGPT mark: https://developers.openai.com/assets/siwc/sign-in-buttons/chatgpt-logo-black.svg
const CHATGPT_CALLBACK_HTML = `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="color-scheme" content="dark">
  <meta name="referrer" content="no-referrer">
  <title>ブラウザ認証完了 · YamabikoChat</title>
  <style>
    /* Visual emphasis: navy / charcoal / light gray / lime = 5 : 2.5 : 1.25 : 1.25. */
    :root { color-scheme: dark; --navy: #131A34; --charcoal: #2F2F2F; --gray: #F5F5F5; --lime: #ADFF00; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; min-height: 100svh; padding: max(28px, env(safe-area-inset-top)) max(24px, env(safe-area-inset-right)) max(24px, env(safe-area-inset-bottom)) max(24px, env(safe-area-inset-left)); background: var(--navy); color: var(--gray); font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; -webkit-font-smoothing: antialiased; }
    .shell { max-width: 1040px; margin: 0 auto; }
    header { display: flex; justify-content: space-between; align-items: center; gap: 16px; padding-bottom: 24px; border-bottom: 1px solid rgb(245 245 245 / 20%); }
    .brand { display: flex; align-items: center; gap: 10px; font-size: 17px; font-weight: 650; letter-spacing: -.4px; }
    .brand svg { width: 30px; height: 30px; color: var(--lime); }
    .header-label { color: rgb(245 245 245 / 65%); font-size: 10px; letter-spacing: 2px; }
    .hero { display: grid; grid-template-columns: 1.35fr 1fr; align-items: center; gap: 48px; padding: 64px 0 56px; }
    .eyebrow { display: flex; align-items: center; gap: 9px; margin: 0 0 24px; color: var(--lime); font-size: 11px; font-weight: 700; letter-spacing: 2px; }
    .eyebrow::before { content: ""; width: 7px; height: 7px; background: var(--lime); border-radius: 50%; }
    h1 { margin: 0; font-size: clamp(32px, 4.5vw, 52px); font-weight: 700; line-height: 1.4; letter-spacing: -1.8px; }
    h1 span { color: var(--lime); }
    .return-link { display: flex; align-items: center; justify-content: space-between; gap: 20px; width: 100%; max-width: 350px; margin-top: 28px; min-height: 60px; padding: 16px 20px; border: 1px solid var(--lime); border-radius: 4px; background: var(--lime); color: var(--navy); font-size: 14px; font-weight: 700; text-decoration: none; line-height: 1.5; }
    .return-link span { font-size: 24px; line-height: 1; }
    .return-link:hover { background: var(--gray); border-color: var(--gray); }
    .return-link:focus-visible { outline: 3px solid var(--gray); outline-offset: 5px; }
    .return-link:active { opacity: .8; }
    .visual { position: relative; display: grid; place-items: center; aspect-ratio: 1; overflow: hidden; border: 1px solid rgb(245 245 245 / 16%); border-radius: 50%; background: repeating-linear-gradient(0deg, transparent 0 39px, rgb(245 245 245 / 5%) 39px 40px), repeating-linear-gradient(90deg, transparent 0 39px, rgb(245 245 245 / 5%) 39px 40px); }
    .visual::before { content: ""; position: absolute; inset: 10%; border: 1px dashed rgb(173 255 0 / 45%); border-radius: 50%; }
    .visual::after { content: ""; position: absolute; width: 9px; height: 9px; right: 13%; top: 24%; border-radius: 50%; background: var(--lime); box-shadow: 0 0 0 6px rgb(173 255 0 / 10%); }
    .check { display: grid; place-items: center; width: 53%; aspect-ratio: 1; border-radius: 50%; background: #fff; color: #000; box-shadow: 0 0 0 12px rgb(173 255 0 / 7%); }
    .check svg { width: 48%; height: 48%; }
    .visual-label { position: absolute; bottom: 14%; font-size: 9px; letter-spacing: 2px; color: var(--gray); }
    .next { display: grid; grid-template-columns: .85fr 1.8fr; background: var(--charcoal); border-radius: 8px; overflow: hidden; }
    .next-heading { display: flex; flex-direction: column; justify-content: space-between; gap: 20px; padding: 28px; }
    .section-label { margin: 0; color: var(--lime); font-size: 10px; letter-spacing: 2px; font-weight: 700; }
    h2 { margin: 0; font-size: 21px; line-height: 1.6; letter-spacing: -.5px; }
    ol { display: grid; grid-template-columns: 1fr 1fr; margin: 0; padding: 0; list-style: none; background: var(--gray); color: var(--navy); color-scheme: light; }
    li { padding: 28px 24px; }
    li + li { border-left: 1px solid rgb(19 26 52 / 15%); }
    .step { display: block; margin-bottom: 20px; font-size: 12px; font-weight: 700; letter-spacing: 1px; }
    h3 { margin: 0 0 10px; font-size: 15px; line-height: 1.5; }
    li p { margin: 0; color: var(--charcoal); font-size: 12px; line-height: 1.9; }
    footer { display: flex; justify-content: space-between; gap: 20px; padding-top: 24px; color: rgb(245 245 245 / 65%); font-size: 11px; line-height: 1.8; }
    footer p { margin: 0; }
    @media (max-width: 700px) {
      .hero { gap: 20px; padding: 40px 0; grid-template-columns: 1fr; }
      .hero-copy { position: relative; }
      .eyebrow { margin-bottom: 20px; font-size: 10px; }
      h1 { font-size: clamp(30px, 7vw, 44px); letter-spacing: -1px; }
      .visual { grid-row: 1; width: 144px; justify-self: end; margin: 0 0 -72px; }
      .visual-label { display: none; }
      .check { box-shadow: 0 0 0 6px rgb(173 255 0 / 7%); }
      .hero-copy { padding-top: 12px; }
      .eyebrow { max-width: calc(100% - 150px); min-height: 40px; line-height: 1.8; }
      .return-link { max-width: none; }
      .next { grid-template-columns: 1fr; }
      .next-heading { flex-direction: row; align-items: center; padding: 20px; }
      h2 { font-size: 17px; }
      li { padding: 22px 18px; }
      .step { margin-bottom: 14px; }
      footer { flex-direction: column; gap: 6px; padding-top: 20px; }
      .header-label { font-size: 9px; letter-spacing: 1px; }
    }
    @media (max-width: 350px) {
      body { padding-left: 16px; padding-right: 16px; }
      .header-label { display: none; }
      .visual { width: 112px; margin-bottom: -62px; }
      .eyebrow { max-width: calc(100% - 118px); }
      .next-heading { padding: 18px; }
      li { padding: 20px 14px; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header>
      <div class="brand">
        <svg viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="m3 25 10-18 5 9 3-5 8 14H3Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="m9 14 4 3 4-3" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>
        YamabikoChat
      </div>
      <span class="header-label">CHATGPT SIGN IN</span>
    </header>
    <main>
      <section class="hero" aria-labelledby="title">
        <div class="hero-copy">
          <p class="eyebrow">BROWSER AUTH COMPLETE</p>
          <h1 id="title">認証が完了。<br><span>会話のつづきへ。</span></h1>
          <!-- APP_RETURN_LINK -->
        </div>
        <div class="visual" aria-hidden="true">
          <div class="check"><svg preserveAspectRatio="none" overflow="visible" style="display: block;" width="21" height="21" viewBox="0 0 21 21" fill="none" xmlns="http://www.w3.org/2000/svg">
<g id="ChatGPT logo &#226;&#128;&#148; original vector">
<path id="Vector" d="M11.8102 19.1625C11.2327 19.1625 10.6841 19.0528 10.1643 18.8334C9.64459 18.6139 9.18259 18.3078 8.77834 17.9151C8.33944 18.0653 7.88322 18.1404 7.40967 18.1404C6.63582 18.1404 5.91972 17.9498 5.26137 17.5686C4.60302 17.1875 4.07172 16.6677 3.66747 16.0094C3.27477 15.351 3.07842 14.6176 3.07842 13.8091C3.07842 13.4742 3.12462 13.1103 3.21702 12.7176C2.75502 12.2903 2.39697 11.7994 2.14287 11.245C1.88877 10.679 1.76172 10.09 1.76172 9.47785C1.76172 8.85415 1.89454 8.25355 2.16019 7.67605C2.42584 7.09855 2.79544 6.6019 3.26899 6.1861C3.75409 5.75875 4.31427 5.46422 4.94952 5.30252C5.07657 4.64417 5.34222 4.05512 5.74647 3.53537C6.16227 3.00407 6.67047 2.58827 7.27107 2.28797C7.87167 1.98767 8.51269 1.83752 9.19414 1.83752C9.77164 1.83752 10.3203 1.94725 10.84 2.1667C11.3598 2.38615 11.8218 2.69222 12.226 3.08492C12.6649 2.93477 13.1211 2.8597 13.5947 2.8597C14.3685 2.8597 15.0846 3.05027 15.743 3.43142C16.4013 3.81257 16.9269 4.33232 17.3196 4.99067C17.7238 5.64902 17.9259 6.38245 17.9259 7.19095C17.9259 7.5259 17.8797 7.88973 17.7873 8.28242C18.2493 8.70977 18.6074 9.20643 18.8615 9.77238C19.1156 10.3268 19.2426 10.91 19.2426 11.5222C19.2426 12.1459 19.1098 12.7465 18.8442 13.324C18.5785 13.9015 18.2031 14.4039 17.718 14.8313C17.2445 15.2471 16.6901 15.5358 16.0548 15.6975C15.9278 16.3559 15.6564 16.9449 15.2406 17.4647C14.8363 17.996 14.3339 18.4118 13.7333 18.7121C13.1327 19.0124 12.4917 19.1625 11.8102 19.1625ZM7.53094 16.9969C8.10844 16.9969 8.61087 16.8756 9.03822 16.6331L12.2953 14.762C12.4108 14.6811 12.4686 14.5714 12.4686 14.4328V12.9429L8.27592 15.351C8.02182 15.5012 7.76772 15.5012 7.51362 15.351L4.23919 13.4626C4.23919 13.4973 4.23342 13.5377 4.22187 13.5839C4.22187 13.6301 4.22187 13.6994 4.22187 13.7918C4.22187 14.3808 4.36047 14.9237 4.63767 15.4203C4.92642 15.9054 5.32489 16.2866 5.83309 16.5638C6.34129 16.8525 6.90724 16.9969 7.53094 16.9969ZM7.70419 14.1729C7.77349 14.2076 7.83702 14.2249 7.89477 14.2249C7.95252 14.2249 8.01027 14.2076 8.06802 14.1729L9.36739 13.4279L5.19207 11.0024C4.93797 10.8523 4.81092 10.6271 4.81092 10.3268V6.56725C4.23342 6.82135 3.77142 7.21405 3.42492 7.74535C3.07842 8.2651 2.90517 8.8426 2.90517 9.47785C2.90517 10.0438 3.04954 10.5866 3.33829 11.1064C3.62704 11.6261 4.00242 12.0189 4.46442 12.2845L7.70419 14.1729ZM11.8102 18.0191C12.4224 18.0191 12.9768 17.8805 13.4734 17.6033C13.9701 17.3261 14.3628 16.9449 14.6515 16.4598C14.9403 15.9747 15.0846 15.4319 15.0846 14.8313V11.0891C15.0846 10.9505 15.0269 10.8465 14.9114 10.7772L13.5947 10.0149V14.8486C13.5947 15.1489 13.4676 15.3741 13.2135 15.5243L9.93912 17.4127C10.5051 17.817 11.1288 18.0191 11.8102 18.0191ZM12.4686 11.6781V9.32192L10.5108 8.21312L8.53579 9.32192V11.6781L10.5108 12.7869L12.4686 11.6781ZM7.40967 6.15145C7.40967 5.85115 7.53672 5.62592 7.79082 5.47577L11.0652 3.58735C10.4993 3.1831 9.87559 2.98097 9.19414 2.98097C8.58199 2.98097 8.02759 3.11957 7.53094 3.39677C7.03429 3.67397 6.64159 4.05512 6.35284 4.54022C6.07564 5.02532 5.93704 5.56817 5.93704 6.16878V9.89365C5.93704 10.0323 5.99479 10.142 6.11029 10.2228L7.40967 10.9851V6.15145ZM16.2108 14.4328C16.7883 14.1787 17.2445 13.786 17.5794 13.2547C17.9259 12.7234 18.0992 12.1459 18.0992 11.5222C18.0992 10.9562 17.9548 10.4134 17.6661 9.89365C17.3773 9.3739 17.0019 8.9812 16.5399 8.71555L13.3002 6.84445C13.2309 6.79825 13.1673 6.78092 13.1096 6.79248C13.0518 6.79248 12.9941 6.8098 12.9363 6.84445L11.637 7.5721L15.8296 10.0149C15.9567 10.0842 16.0491 10.1766 16.1068 10.2921C16.1761 10.3961 16.2108 10.5231 16.2108 10.6733V14.4328ZM12.7284 5.6317C12.9825 5.47 13.2366 5.47 13.4907 5.6317L16.7825 7.55477C16.7825 7.47393 16.7825 7.36997 16.7825 7.24292C16.7825 6.68852 16.6439 6.163 16.3667 5.66635C16.101 5.15815 15.7141 4.7539 15.2059 4.4536C14.7093 4.1533 14.1318 4.00315 13.4734 4.00315C12.8959 4.00315 12.3935 4.12442 11.9661 4.36697L8.70904 6.23808C8.59354 6.31892 8.53579 6.42865 8.53579 6.56725V8.0572L12.7284 5.6317Z" fill="black"/>
</g>
</svg></div>
          <span class="visual-label">AUTH / COMPLETE</span>
        </div>
      </section>
      <section class="next" aria-labelledby="next-title">
        <div class="next-heading">
          <p class="section-label">NEXT STEP</p>
          <h2 id="next-title">あと少しで、<br>準備完了。</h2>
        </div>
        <ol>
          <li><span class="step" aria-hidden="true">01 / RETURN</span><h3>アプリに戻る</h3><p>アプリ切り替え、または画面左上の「YamabikoChat」から戻ります。</p></li>
          <li><span class="step" aria-hidden="true">02 / CHECK</span><h3>接続を確認する</h3><p>アプリの設定画面で、ChatGPTの接続状態を確認してください。</p></li>
        </ol>
      </section>
    </main>
    <footer><p>接続が確認できたら、このタブは閉じてかまいません。</p><p>あなたの会話を、ここから。</p></footer>
  </div>
</body>
</html>`;

function chatGPTCallbackHTML(userAgent = "") {
  // iPad Safari can identify as Macintosh. Android has no registered app scheme.
  const supportsAppReturn = /iPhone|iPad|iPod|Macintosh/.test(userAgent);
  // This fixed link only foregrounds iOS; credentials still resolve through Pi.
  return CHATGPT_CALLBACK_HTML.replace("<!-- APP_RETURN_LINK -->", supportsAppReturn
    ? '<a class="return-link" href="yamabikochat://auth/complete">YamabikoChatに戻る <span aria-hidden="true">↗</span></a>'
    : "");
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
      throw Object.assign(failure(typeof code === "string" ? code : "chatgpt_request_failed", `ChatGPT request failed (${response.status})`), { statusCode: response.status });
    }
    return response.json();
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
