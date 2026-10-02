import assert from "node:assert/strict";
import { once } from "node:events";
import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import test from "node:test";

for (const [incompleteReason, terminalTurn] of [[null, 2], ["max_output_tokens", 2], ["content_filter", 2], ["max_output_tokens", 1]]) test(`bundled Pi SIWC tool loop terminal status: ${incompleteReason ?? "completed"}, turn ${terminalTurn}`, { timeout: 20_000 }, async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "yamabiko-siwc-bridge-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const mock = path.join(root, "mock.mjs");
  const joseURL = new URL("../node_modules/jose/dist/webapi/index.js", import.meta.url).href;
  fs.writeFileSync(mock, `
    import {generateKeyPair,exportJWK,SignJWT} from ${JSON.stringify(joseURL)};
    const {publicKey,privateKey}=await generateKeyPair('RS256');
    const jwk={...await exportJWK(publicKey),alg:'RS256',kid:'bridge'};
    const original=globalThis.fetch;
    let responses=0;
    globalThis.fetch=async (url, options={})=>{
      const value=String(url);
      if(value.includes('chatgpt.com')) throw new Error('Legacy ChatGPT route is forbidden');
      if(value.startsWith('http://127.0.0.1:')) return original(url,options);
      if(value.endsWith('openid-configuration'))return Response.json({issuer:'https://auth.openai.com',authorization_endpoint:'https://auth.openai.com/api/accounts/authorize',token_endpoint:'https://auth.openai.com/api/accounts/oauth/token',jwks_uri:'https://auth.openai.com/.well-known/jwks.json',revocation_endpoint:'https://auth.openai.com/oauth/revoke'});
      if(value.endsWith('jwks.json'))return Response.json({keys:[jwk]});
      if(value.endsWith('oauth/token')) {
        const params=new URLSearchParams(options.body);
        const nonce=params.get('code');
        const idToken=await new SignJWT({nonce,email:'bridge@example.com'}).setProtectedHeader({alg:'RS256',kid:'bridge'}).setIssuer('https://auth.openai.com').setAudience(params.get('client_id')).setSubject('bridge-subject').setIssuedAt().setExpirationTime('1h').sign(privateKey);
        return Response.json({access_token:'bridge-access',refresh_token:'bridge-refresh',id_token:idToken,token_type:'Bearer',expires_in:3600,scope:'openid email profile offline_access resource.invoke chatgpt.tokens.use.direct'});
      }
      if(value==='https://api.openai.com/v1/models')return Response.json({models:[{slug:'future-model',display_name:'Future',visibility:'list'},{slug:'gpt-6-sol',display_name:'Account Sol',visibility:'list'}]});
      if(value==='https://api.openai.com/v1/responses') {
        const payload=JSON.parse(options.body);
        if(!payload.stream||payload.store!==false||payload.temperature!==undefined||payload.max_output_tokens!==undefined)throw new Error('Wrong SIWC preview payload');
        if(payload.tools?.[0]?.type!=='namespace')throw new Error('Local tools must be namespaced');
        responses++;
        if(responses>${terminalTurn})throw new Error("Unexpected inference after terminal response");
        const item=responses===1?{type:'function_call',id:'fc_bridge',call_id:'call_bridge',name:'local_echo',namespace:'yamabiko',arguments:'{}',status:'completed'}:{type:'message',id:'msg_bridge',role:'assistant',status:'completed',content:[{type:'output_text',text:'Hello from ChatGPT plan',annotations:[]}]};
        const incompleteReason=${JSON.stringify(incompleteReason)};
        const events=[{type:'response.created',response:{id:'resp_bridge',status:'in_progress'}},{type:'response.output_item.added',output_index:0,item:{...item,arguments:responses===1?'':undefined}},{type:'response.output_item.done',output_index:0,item},{type:incompleteReason && responses>=${terminalTurn}?'response.incomplete':'response.completed',response:{id:'resp_bridge',status:incompleteReason && responses>=${terminalTurn}?'incomplete':'completed',...(incompleteReason && responses>=${terminalTurn}?{incomplete_details:{reason:incompleteReason}}:{}),output:[item],usage:{input_tokens:2,output_tokens:1,total_tokens:3}}}];
        return new Response(events.map(e=>'event: '+e.type+'\\ndata: '+JSON.stringify(e)+'\\n\\n').join(''),{headers:{'content-type':'text/event-stream'}});
      }
      if(value.endsWith('/oauth/revoke'))return new Response(null,{status:200});
      throw new Error('Unexpected SIWC endpoint '+value);
    };
  `);
  const listener = net.createServer().listen(0, "127.0.0.1");
  await once(listener, "listening");
  const port = listener.address().port;
  listener.close();
  await once(listener, "close");
  const child = spawn(process.execPath, ["--import", mock, new URL("../bundle/main.js", import.meta.url).pathname, String(port), "siwc-test"], { stdio: ["ignore", "ignore", "pipe"] });
  t.after(() => child.kill());
  let stderr = "";
  child.stderr.on("data", value => stderr += value);
  const base = `http://127.0.0.1:${port}`;
  const headers = { authorization: "Bearer siwc-test", "content-type": "application/json" };
  const post = (route, body) => fetch(base + route, { method: "POST", headers, body: JSON.stringify(body) });
  for (let i = 0; ; i++) {
    try { if ((await fetch(base + "/health", { headers })).ok) break; } catch {}
    assert.ok(i < 100, stderr);
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  async function* events(response) {
    assert.equal(response.status, 200);
    let buffered = "";
    for await (const chunk of response.body) {
      buffered += new TextDecoder().decode(chunk);
      while (buffered.includes("\n")) {
        const index = buffered.indexOf("\n"), line = buffered.slice(0, index);
        buffered = buffered.slice(index + 1);
        if (line) yield JSON.parse(line);
      }
    }
  }
  let registration, credential;
  for await (const event of events(await post("/v1/auth/login", { provider: "chatgpt", method: "browser", context: { hostId: "urn:uuid:12345678-1234-4123-8123-123456789abc" } }))) {
    assert.notEqual(event.type, "error", event.message);
    if (event.type === "auth_url") {
      const authorization = new URL(event.url);
      assert.equal(authorization.searchParams.get("agent_name_hint"), "YamabikoChat");
      const callback = new URL(authorization.searchParams.get("redirect_uri"));
      callback.search = new URLSearchParams({ state: authorization.searchParams.get("state"), code: authorization.searchParams.get("nonce"), client_id: "oaiapp_bridge" });
      assert.equal((await fetch(callback)).status, 200);
    }
    if (event.type === "auth_registration") {
      registration = event.registration;
      assert.equal(registration.clientId, "oaiapp_bridge");
      assert.equal((await post("/v1/auth/registration", { requestId: event.requestId })).status, 200);
    }
    if (event.type === "auth_completed") {
      assert.ok(registration);
      credential = event.credential;
      assert.equal(event.profile.planUsageEnabled, true);
    }
  }
  assert.ok(credential);
  const catalog = await (await post("/v1/models/chatgpt", { credential })).json();
  assert.deepEqual(catalog.models.map(model => model.id), ["future-model", "gpt-6-sol"]);
  assert.equal(catalog.models[0].reason, "pi_model_missing");
  const resolutions = await (await post("/v1/models/resolve", { models: [{ contractVersion: 2, provider: "openai-chatgpt", model: "gpt-6-sol" }, { contractVersion: 2, provider: "openai-chatgpt", model: "future-model" }] })).json();
  assert.equal(resolutions.models[0].source, "pi_builtin");
  assert.equal(resolutions.models[1].supported, false);
  let completed, failure, toolExecutions = 0;
  const llmSuccess = [];
  const envelope = {
    runId: "siwc-run", config: { contractVersion: 2, provider: "openai-chatgpt", model: "gpt-6-sol", apiKey: credential.access },
    request: { messages: [{ role: "user", content: "hello", attachments: [] }], systemPrompt: "Be helpful", tools: [{ type: "function", payload: { name: "local_echo", description: "Local echo", parameters: '{"type":"object","properties":{}}' } }], metadata: { temperature: "0.2" } }
  };
  for await (const event of events(await post("/v1/run", envelope))) {
    if (event.type === "error") failure = event;
    if (event.type === "llm_end") llmSuccess.push(event.succeeded);
    if (event.type === "tool_request") {
      toolExecutions++;
      assert.equal(event.name, "local_echo");
      await post("/v1/tool-result", { requestId: event.requestId, content: "local result", isError: false, status: "complete" });
    }
    if (event.type === "completed") completed = event.response;
  }
  assert.equal(toolExecutions, terminalTurn === 1 ? 0 : 1);
  if (incompleteReason) {
    assert.equal(completed, undefined);
    assert.match(failure.message, new RegExp(`incomplete.*${incompleteReason}`));
    assert.deepEqual(llmSuccess, terminalTurn === 1 ? [false] : [true, false]);
  } else {
    assert.equal(failure, undefined);
    assert.equal(completed.text, "Hello from ChatGPT plan");
    assert.deepEqual(llmSuccess, [true, true]);
  }
  assert.equal((await post("/v1/auth/revoke", { provider: "chatgpt", credential })).status, 200);
  const afterLogout = await (await post("/v1/models/resolve", { models: [{ contractVersion: 2, provider: "openai-chatgpt", model: "gpt-6-sol" }] })).json();
  assert.equal(afterLogout.models[0].reason, "chatgpt_catalog_required");
});

test("bundled Pi SIWC run executes a models.dev contract slug through openai-responses", { timeout: 20_000 }, async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "yamabiko-siwc-contract-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const mock = path.join(root, "mock.mjs");
  const joseURL = new URL("../node_modules/jose/dist/webapi/index.js", import.meta.url).href;
  fs.writeFileSync(mock, `
    import {generateKeyPair,exportJWK,SignJWT} from ${JSON.stringify(joseURL)};
    const {publicKey,privateKey}=await generateKeyPair('RS256');
    const jwk={...await exportJWK(publicKey),alg:'RS256',kid:'bridge'};
    const original=globalThis.fetch;
    globalThis.fetch=async (url, options={})=>{
      const value=String(url);
      if(value.includes('chatgpt.com')) throw new Error('Legacy ChatGPT route is forbidden');
      if(value.startsWith('http://127.0.0.1:')) return original(url,options);
      if(value.endsWith('openid-configuration'))return Response.json({issuer:'https://auth.openai.com',authorization_endpoint:'https://auth.openai.com/api/accounts/authorize',token_endpoint:'https://auth.openai.com/api/accounts/oauth/token',jwks_uri:'https://auth.openai.com/.well-known/jwks.json',revocation_endpoint:'https://auth.openai.com/oauth/revoke'});
      if(value.endsWith('jwks.json'))return Response.json({keys:[jwk]});
      if(value.endsWith('oauth/token')) {
        const params=new URLSearchParams(options.body);
        const nonce=params.get('code');
        const idToken=await new SignJWT({nonce,email:'bridge@example.com'}).setProtectedHeader({alg:'RS256',kid:'bridge'}).setIssuer('https://auth.openai.com').setAudience(params.get('client_id')).setSubject('bridge-subject').setIssuedAt().setExpirationTime('1h').sign(privateKey);
        return Response.json({access_token:'bridge-access',refresh_token:'bridge-refresh',id_token:idToken,token_type:'Bearer',expires_in:3600,scope:'openid email profile offline_access resource.invoke chatgpt.tokens.use.direct'});
      }
      if(value==='https://api.openai.com/v1/models')return Response.json({models:[{slug:'gpt-6.1-sol',display_name:'GPT 6.1 Sol',visibility:'list'}]});
      if(value==='https://api.openai.com/v1/responses') {
        const payload=JSON.parse(options.body);
        if(payload.model!=='gpt-6.1-sol'||!payload.stream||payload.store!==false)throw new Error('Wrong SIWC preview payload');
        const item={type:'message',id:'msg_bridge',role:'assistant',status:'completed',content:[{type:'output_text',text:'Hello from ChatGPT plan',annotations:[]}]};
        const events=[{type:'response.created',response:{id:'resp_bridge',status:'in_progress'}},{type:'response.output_item.done',output_index:0,item},{type:'response.completed',response:{id:'resp_bridge',status:'completed',output:[item],usage:{input_tokens:2,output_tokens:1,total_tokens:3}}}];
        return new Response(events.map(e=>'event: '+e.type+'\\ndata: '+JSON.stringify(e)+'\\n\\n').join(''),{headers:{'content-type':'text/event-stream'}});
      }
      if(value.endsWith('/oauth/revoke'))return new Response(null,{status:200});
      throw new Error('Unexpected SIWC endpoint '+value);
    };
  `);
  const listener = net.createServer().listen(0, "127.0.0.1");
  await once(listener, "listening");
  const port = listener.address().port;
  listener.close();
  await once(listener, "close");
  const child = spawn(process.execPath, ["--import", mock, new URL("../bundle/main.js", import.meta.url).pathname, String(port), "siwc-test"], { stdio: ["ignore", "ignore", "pipe"] });
  t.after(() => child.kill());
  let stderr = "";
  child.stderr.on("data", value => stderr += value);
  const base = `http://127.0.0.1:${port}`;
  const headers = { authorization: "Bearer siwc-test", "content-type": "application/json" };
  const post = (route, body) => fetch(base + route, { method: "POST", headers, body: JSON.stringify(body) });
  for (let i = 0; ; i++) {
    try { if ((await fetch(base + "/health", { headers })).ok) break; } catch {}
    assert.ok(i < 100, stderr);
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  async function* events(response) {
    assert.equal(response.status, 200);
    let buffered = "";
    for await (const chunk of response.body) {
      buffered += new TextDecoder().decode(chunk);
      while (buffered.includes("\n")) {
        const index = buffered.indexOf("\n"), line = buffered.slice(0, index);
        buffered = buffered.slice(index + 1);
        if (line) yield JSON.parse(line);
      }
    }
  }
  let credential;
  for await (const event of events(await post("/v1/auth/login", { provider: "chatgpt", method: "browser", context: { hostId: "urn:uuid:12345678-1234-4123-8123-123456789abc" } }))) {
    assert.notEqual(event.type, "error", event.message);
    if (event.type === "auth_url") {
      const authorization = new URL(event.url);
      const callback = new URL(authorization.searchParams.get("redirect_uri"));
      callback.search = new URLSearchParams({ state: authorization.searchParams.get("state"), code: authorization.searchParams.get("nonce"), client_id: "oaiapp_bridge" });
      assert.equal((await fetch(callback)).status, 200);
    }
    if (event.type === "auth_registration") {
      assert.equal((await post("/v1/auth/registration", { requestId: event.requestId })).status, 200);
    }
    if (event.type === "auth_completed") credential = event.credential;
  }
  assert.ok(credential);
  const contract = {
    provenance: "provider", npm: "@ai-sdk/openai", name: "GPT 6.1 Sol",
    reasoning: true, input: ["text", "image"], contextWindow: 1050000, maxTokens: 128000,
    reasoningEfforts: ["low", "medium", "high", "xhigh", "max"], toolCall: true
  };
  const catalog = await (await post("/v1/models/chatgpt", { credential, contracts: { "gpt-6.1-sol": contract } })).json();
  const entry = catalog.models.find(model => model.id === "gpt-6.1-sol");
  assert.equal(entry.supported, true);
  assert.equal(entry.source, "models_dev_contract");
  assert.deepEqual(entry.supportedThinkingLevels, ["low", "medium", "high", "xhigh", "max"]);
  const resolutions = await (await post("/v1/models/resolve", { models: [{ contractVersion: 2, provider: "openai-chatgpt", model: "gpt-6.1-sol" }] })).json();
  assert.equal(resolutions.models[0].supported, true);
  assert.equal(resolutions.models[0].source, "models_dev_contract");
  let completed, failure;
  const envelope = {
    runId: "siwc-contract-run",
    config: { contractVersion: 2, provider: "openai-chatgpt", model: "gpt-6.1-sol", apiKey: credential.access, catalogContract: contract },
    request: { messages: [{ role: "user", content: "hello", attachments: [] }], tools: [] }
  };
  for await (const event of events(await post("/v1/run", envelope))) {
    if (event.type === "error") failure = event;
    if (event.type === "completed") completed = event.response;
  }
  assert.equal(failure, undefined);
  assert.equal(completed.text, "Hello from ChatGPT plan");
  assert.equal(completed.piExecution.resolution.source, "models_dev_contract");
});
