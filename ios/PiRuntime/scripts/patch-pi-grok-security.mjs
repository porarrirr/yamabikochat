// Small, drift-checked fixes inside the pinned Pi OAuth provider; no alternate auth flow.
import fs from 'node:fs';
const root = new URL('../node_modules/pi-grok/', import.meta.url);
const pkg = JSON.parse(fs.readFileSync(new URL('package.json', root)));
const lock = JSON.parse(fs.readFileSync(new URL('../package-lock.json', import.meta.url)));
const pinned = 'https://github.com/stnly/pi-grok/archive/8b304e65c088f84ccb932959d97739245fe47d97.tar.gz';
if (pkg.version !== '0.10.1' || lock.packages['node_modules/pi-grok'].resolved !== pinned) {
  throw new Error('Review pi-grok security patch for the new upstream version');
}
function patch(name, before, after) {
  const file = new URL(name, root);
  const source = fs.readFileSync(file, 'utf8');
  if (source.includes(after)) return;
  if (source.split(before).length !== 2) throw new Error(`pi-grok security patch drift: ${name}`);
  fs.writeFileSync(file, source.replace(before, after));
}
patch('bounded-json.ts',
  '`JSON response was not parseable: ${cause instanceof Error ? cause.message : String(cause)}`',
  '"JSON response was not parseable."');
patch('oauth.ts', 'const DEFAULT_CALLBACK_PORT = 56121;', 'const DEFAULT_CALLBACK_PORT = 0; // private ephemeral listener');
patch('oauth.ts', 'function startCallbackServer(): Promise<{', 'function startCallbackServer(expectedState: string): Promise<{');
patch('oauth.ts', 'const callback = await startCallbackServer();', 'const callback = await startCallbackServer(state);');
patch('oauth.ts', 'const server = createServer((req, res) => {', `const server = createServer((req, res) => {
        res.setHeader("Cache-Control", "no-store");
        res.setHeader("Referrer-Policy", "no-referrer");`);
patch('oauth.ts', 'if (url.pathname !== CALLBACK_PATH) {', 'if (req.method !== "GET" || url.pathname !== CALLBACK_PATH) {');
patch('oauth.ts', '\t\t\tif (served) {', `            // Validate even error callbacks before consuming this authorization attempt.
            if (result.state !== expectedState || (!result.error && !result.code)) {
                res.statusCode = 400;
                res.end("xAI callback rejected.");
                return;
            }
\t\t\tif (served) {`);
patch('oauth.ts', 'r.errorDescription ?? r.error ?? "xAI authorization failed."', '"xAI authorization failed."');
patch('oauth.ts', 'if (!isXaiOrigin(url)) {', 'if (!isXaiOrigin(url) || url.origin !== ISSUER || url.username || url.password || url.hash) {');
patch('oauth.ts', '\ttoken_endpoint: string;', '\ttoken_endpoint: string;\n    revocation_endpoint?: string;');
patch('oauth.ts', '\tconst authorizationEndpoint = validateEndpoint', `    if (payload.issuer !== ISSUER) {
        throw new XaiOAuthError("Unexpected xAI issuer", XaiErrorCode.DISCOVERY_INVALID_ORIGIN);
    }
\tconst authorizationEndpoint = validateEndpoint`);
patch('oauth.ts', '\t\ttoken_endpoint: tokenEndpoint,', `\t\ttoken_endpoint: tokenEndpoint,
        revocation_endpoint: payload.revocation_endpoint === undefined ? undefined : validateEndpoint(String(payload.revocation_endpoint), "revocation_endpoint"),`);
const revoke = fs.readFileSync(new URL('./patches/pi-grok-revoke.ts', import.meta.url), 'utf8');
const oauthFile = new URL('oauth.ts', root);
const oauth = fs.readFileSync(oauthFile, 'utf8');
if (!oauth.includes(revoke)) {
  if (oauth.includes('export async function revoke(')) throw new Error('Review upstream pi-grok revoke implementation');
  fs.appendFileSync(oauthFile, revoke);
}
