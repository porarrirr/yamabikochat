// Authentication failures must never carry response bodies, parser excerpts, or causes.
const codes = new Set([
  "access_denied", "invalid_grant", "invalid_client", "invalid_scope", "invalid_request",
  "unauthorized_client", "unsupported_grant_type", "temporarily_unavailable", "server_error",
  "oauth_signed_out", "oauth_cancelled", "oauth_timeout", "oauth_request_failed",
  "discovery_failed", "discovery_invalid_origin", "authorization_failed", "state_mismatch",
  "code_missing", "token_exchange_failed", "token_exchange_invalid", "id_token_invalid",
  "id_token_signature_invalid", "refresh_missing", "refresh_failed", "auth_missing",
  "device_code_failed", "xai_revocation_unsupported", "xai_revocation_failed",
  "chatgpt_account_mismatch", "chatgpt_callback_invalid", "chatgpt_catalog_invalid",
  "chatgpt_catalog_superseded", "chatgpt_client_mismatch", "chatgpt_contract_invalid",
  "chatgpt_discovery_invalid", "chatgpt_host_invalid", "chatgpt_identity_invalid",
  "chatgpt_issuer_mismatch", "chatgpt_login_busy", "chatgpt_nonce_mismatch",
  "chatgpt_plan_permission_required", "chatgpt_reconnect_required",
  "chatgpt_refresh_not_yet_allowed", "chatgpt_registration_incomplete",
  "chatgpt_registration_invalid", "chatgpt_revocation_failed", "chatgpt_state_mismatch",
  "chatgpt_response_invalid", "chatgpt_request_failed"
]);

export function safeOAuthCode(value) {
  return typeof value === "string" && codes.has(value) ? value : "oauth_request_failed";
}

export function authFailure(error) {
  const code = error?.name === "AbortError" ? "oauth_cancelled"
    : error?.name === "TimeoutError" ? "oauth_timeout" : safeOAuthCode(error?.code);
  const message = code === "oauth_signed_out" ? "OAuth session was signed out" : `Authentication failed (${code})`;
  const statusCode = error?.statusCode;
  return Object.assign(new Error(message), { code,
    ...(Number.isInteger(statusCode) && statusCode >= 400 && statusCode <= 599 ? { statusCode } : {}) });
}
