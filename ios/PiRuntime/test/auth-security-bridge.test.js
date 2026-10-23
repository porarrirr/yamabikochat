import assert from 'node:assert/strict';
import test from 'node:test';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { once } from 'node:events';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

async function runtime(t, transport) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'yamabiko-auth-security-'));
  fs.copyFileSync(new URL('../bundle/main.js', import.meta.url), path.join(root, 'main.mjs'));
  fs.cpSync(new URL('../bundle/PiAssets', import.meta.url), path.join(root, 'PiAssets'), { recursive: true });
  const eventsFile = path.join(root, 'events.jsonl');
  fs.writeFileSync(path.join(root, 'offline.mjs'), `
    import fs from 'node:fs';
    const record = value => fs.appendFileSync(${JSON.stringify(eventsFile)},JSON.stringify(value)+'\\n');
    const original = globalThis.fetch;
    globalThis.fetch = async(input, options={}) => {
      const url=String(input);
      if(url.startsWith('http://127.0.0.1:')) return original(input,options);
      ${transport}
      throw new Error('Unexpected external request blocked by offline fixture');
    };
  `);
  const probe = createServer(); await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = probe.address().port; await new Promise(resolve => probe.close(resolve));
  const child = spawn(process.execPath, ['--import', path.join(root, 'offline.mjs'), path.join(root, 'main.mjs'), String(port), 'synthetic-loopback-auth'], { cwd: root, stdio: ['ignore', 'ignore', 'pipe'] });
  let stderr = ''; child.stderr.on('data', chunk => stderr += chunk);
  t.after(async () => {
    if (child.exitCode === null) { child.kill(); await once(child, 'exit'); }
    fs.rmSync(root, { recursive: true, force: true });
  });
  const headers = { authorization: 'Bearer synthetic-loopback-auth', 'content-type': 'application/json' };
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(base + '/health', { headers })).ok) break; } catch {}
    assert.ok(attempt < 200, stderr);
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  return {
    post: (route, body) => fetch(base + route, { method: 'POST', headers, body: JSON.stringify(body) }),
    events: () => fs.existsSync(eventsFile) ? fs.readFileSync(eventsFile, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : []
  };
}
const discovery = (issuer, extra = {}) => ({ issuer, authorization_endpoint: issuer + '/oauth2/authorize', token_endpoint: issuer + '/oauth2/token', jwks_uri: issuer + '/.well-known/jwks.json', revocation_endpoint: issuer + '/oauth2/revoke', ...extra });
const grokCredential = () => ({ type: 'oauth', access: 'synthetic-old-access', refresh: 'synthetic-old-refresh', expires: Date.now() + 3600_000, tokenEndpoint: 'https://auth.x.ai/oauth2/token' });

test('malformed token bodies and attacker-supplied error codes never reach OAuth bridge errors', { timeout: 30_000 }, async t => {
  const r = await runtime(t, `
    if(url.endsWith('openid-configuration'))return Response.json(${JSON.stringify(discovery('https://auth.openai.com'))});
    if(url.includes('/oauth2/token')) {
      const forceRaw=options.body.get('refresh_token').includes('raw');
      return forceRaw ? new Response('NEW-UNKNOWN-SECRET',{status:200}) : Response.json({error:'NEW-UNKNOWN-SECRET'},{status:400});
    }
  `);
  for (const provider of ['chatgpt', 'supergrok']) for (const form of ['raw', 'error-code']) {
    const credential = { ...grokCredential(), refresh: `synthetic-${form}`, expires: 0,
      ...(provider === 'chatgpt' ? { contract: 'siwc-v1', clientId: 'oaiapp_security', hostId: 'urn:uuid:12345678-1234-4123-8123-123456789abc', issuer: 'https://auth.openai.com', subject: 'synthetic-user', accessExpiresAt: 0, scopes: ['chatgpt.tokens.use.direct'] } : {}) };
    const response = await r.post('/v1/auth/resolve', { provider, credential, force: true });
    const body = await response.text();
    assert.equal(response.status, 500);
    assert.ok(!body.includes('NEW-UNKNOWN-SECRET'), body);
    assert.match(body, /Authentication failed/);
  }
});

test('SuperGrok revokes the rotated session at its discovered endpoint and clears runtime auth', { timeout: 30_000 }, async t => {
  const r = await runtime(t, `
    if(url.endsWith('openid-configuration'))return Response.json(${JSON.stringify(discovery('https://auth.x.ai'))});
    if(url.endsWith('/oauth2/token')) {
      record({type:'refresh-start'});
      await new Promise(resolve=>setTimeout(resolve,100));
      return Response.json({access_token:'synthetic-rotated-access',refresh_token:'synthetic-rotated-refresh',expires_in:3600,token_type:'Bearer'});
    }
    if(url.endsWith('/oauth2/revoke')) {
      record({type:'revoke',url,token:options.body.get('token'),hint:options.body.get('token_type_hint'),client:options.body.get('client_id'),redirect:options.redirect});
      return new Response(null,{status:200});
    }
  `);
  const credential = grokCredential();
  assert.equal((await r.post('/v1/auth/resolve', { provider: 'supergrok', credential })).status, 200);
  const refresh = r.post('/v1/auth/resolve', { provider: 'supergrok', credential, force: true });
  for (let attempt = 0; !r.events().some(event => event.type === 'refresh-start'); attempt++) {
    assert.ok(attempt < 100); await new Promise(resolve => setTimeout(resolve, 5));
  }
  const revoked = await r.post('/v1/auth/revoke', { provider: 'supergrok', credential });
  assert.equal((await refresh).status, 200);
  assert.equal(revoked.status, 200, await revoked.text());
  const calls = r.events().filter(event => event.type === 'revoke');
  assert.deepEqual(calls.map(call => [call.token, call.hint]), [
    ['synthetic-rotated-refresh', 'refresh_token'], ['synthetic-rotated-access', 'access_token']
  ]);
  assert.ok(calls.every(call => call.url === 'https://auth.x.ai/oauth2/revoke' && call.client && call.redirect === 'error'));
  assert.equal((await r.post('/v1/auth/resolve', { provider: 'supergrok', credential })).status, 500);
});

test('missing or failed revocation fails visibly and never falls back to an inferred endpoint', { timeout: 30_000 }, async t => {
  for (const mode of ['missing', 'failed', 'untrusted-origin']) {
    await t.test(mode, async t => {
      const metadata = discovery('https://auth.x.ai');
      if (mode === 'missing') delete metadata.revocation_endpoint;
      if (mode === 'untrusted-origin') metadata.revocation_endpoint = 'https://attacker.example/revoke';
      const r = await runtime(t, `
        if(url.endsWith('openid-configuration'))return Response.json(${JSON.stringify(metadata)});
        if(url==='https://auth.x.ai/oauth2/revoke'){record({type:'revoke'});return new Response('NEW-UNKNOWN-SECRET',{status:503});}
      `);
      const credential = grokCredential();
      const response = await r.post('/v1/auth/revoke', { provider: 'supergrok', credential });
      const body = await response.text();
      assert.equal(response.status, 500); assert.ok(!body.includes('NEW-UNKNOWN-SECRET'));
      assert.equal(r.events().length, mode === 'failed' ? 1 : 0);
      assert.equal((await r.post('/v1/auth/resolve', { provider: 'supergrok', credential })).status, 500);
    });
  }
});

test('SuperGrok ignores wrong-state and non-GET callbacks before accepting a matching denial', { timeout: 30_000 }, async t => {
  const r = await runtime(t, `
    if(url.endsWith('openid-configuration'))return Response.json(${JSON.stringify(discovery('https://auth.x.ai'))});
  `);
  const response = await r.post('/v1/auth/login', { provider: 'supergrok', method: 'browser' });
  let events = '', sawURL = false;
  for await (const bytes of response.body) {
    const chunk = Buffer.from(bytes).toString('utf8'); events += chunk;
    const auth = chunk.split('\n').filter(Boolean).map(JSON.parse).find(event => event.type === 'auth_url');
    if (!auth) continue;
    sawURL = true;
    const url = new URL(auth.url), callback = new URL(url.searchParams.get('redirect_uri'));
    const state = url.searchParams.get('state');
    callback.search = new URLSearchParams({ state: 'wrong', error: 'access_denied', error_description: 'NEW-UNKNOWN-SECRET' });
    const wrong = await fetch(callback);assert.equal(wrong.status, 400);assert.equal(wrong.headers.get('cache-control'), 'no-store');
    callback.search = new URLSearchParams({ state, code: 'synthetic-code' });
    assert.equal((await fetch(callback, { method: 'POST' })).status, 404);
    callback.search = new URLSearchParams({ state, error: 'access_denied', error_description: 'NEW-UNKNOWN-SECRET' });
    assert.equal((await fetch(callback)).status, 400);
  }
  assert.ok(sawURL);assert.match(events, /"type":"error"/);
  assert.ok(!events.includes('NEW-UNKNOWN-SECRET'));
});

test('restricted and legacy secret requests cannot execute an undeclared child or disclose data to it', { timeout: 30_000 }, async t => {
  const requests = [];
  const provider = createServer(async (req, res) => {
    let input = '';for await (const chunk of req) input += chunk;
    const body = JSON.parse(input); requests.push(body);
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    const emit = (delta, finish_reason = null) => res.write(`data: ${JSON.stringify({ id: 'security', object: 'chat.completion.chunk', model: body.model, choices: [{ index: 0, delta, finish_reason }] })}\n\n`);
    if (body.messages.at(-1).role !== 'tool') {
      emit({ role: 'assistant', tool_calls: [{ index: 0, id: 'unrequested-child', type: 'function', function: { name: 'subagent', arguments: JSON.stringify({ agent: 'delegate', task: 'SYNTHETIC_PRIVATE_MESSAGE', async: false }) } }] });
      emit({}, 'tool_calls');
    } else { emit({ role: 'assistant', content: 'Finished without delegation' });emit({}, 'stop'); }
    res.end('data: [DONE]\n\n');
  });
  await new Promise(resolve => provider.listen(0, '127.0.0.1', resolve));
  t.after(() => { provider.closeAllConnections();provider.close(); });
  const r = await runtime(t, `record({type:'external-request'});return new Response(null,{status:500});`);
  const config = { contractVersion: 2, provider: 'yamabiko-custom', model: 'security-parent', apiKey: 'synthetic-key', thinkingLevel: 'off',
    customEndpoint: { name: 'Security', protocol: 'openai-completions', modelId: 'security-parent', baseUrl: `http://127.0.0.1:${provider.address().port}/v1`, contextWindow: 8192, maxTokens: 1024, reasoning: false, toolCall: true, vision: false, reasoningEffort: 'off', maxTokensField: 'max_tokens' },
    subagents: { enabled: true, defaultModelID: 'other-provider', models: [{ id: 'other-provider', name: 'Child', configuration: { contractVersion: 2, provider: 'google', model: 'gemini-2.5-flash', apiKey: 'synthetic-child-key', thinkingLevel: 'off' } }] } };
  for (const policy of [
    { executionPolicy: { allowsClientTools: false, allowsSubagents: false }, metadata: { supportsClientTools: 'true', subagentsEnabled: 'true' } },
    { metadata: { supportsClientTools: 'false', subagentsEnabled: 'true' } }
  ]) {
    const request = { messages: [{ role: 'user', content: 'SYNTHETIC_PRIVATE_MESSAGE', attachments: [] }], tools: [], ...policy };
    const events = await (await r.post('/v1/run', { runId: crypto.randomUUID(), config, request })).text();
    assert.ok(!events.includes('"type":"subagent_update"'));
    assert.match(events, /"type":"completed"/);
  }
  assert.ok(requests.length >= 2);
  assert.ok(requests.every(body => !body.tools?.length));
  assert.deepEqual(r.events(), [], 'No child-provider discovery or inference may occur');
});
