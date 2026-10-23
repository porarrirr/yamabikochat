import assert from 'node:assert/strict';
import test from 'node:test';
import { builtinModels } from '@earendil-works/pi-ai/providers/all';
import { enforceExecutionPolicy } from '../src/execution-policy.js';
import { authFailure } from '../src/auth-security.js';
import { OAuthOperations } from '../src/oauth-operations.js';

test('host restrictions remove child credentials and tools for every Pi provider/model/protocol', () => {
  const protocols = new Set();
  let checked = 0;
  for (const model of builtinModels().getModels()) {
    const config = { provider: model.provider, model: model.id, apiKey: 'parent-key', subagents: { enabled: true, models: [{ configuration: { apiKey: 'child-key' } }] } };
    for (const restriction of [
      { executionPolicy: { allowsClientTools: false, allowsSubagents: false } },
      { metadata: { supportsClientTools: 'false', subagentsEnabled: 'true' } }
    ]) {
      const result = enforceExecutionPolicy({ tools: [{ type: 'function' }], skillContext: {}, ...restriction }, config);
      assert.equal(result.config.subagents, undefined);
      assert.equal(result.config.apiKey, 'parent-key');
      assert.deepEqual(result.request.tools, []);
      assert.equal(result.request.skillContext, null);
      assert.equal(config.subagents.enabled, true, 'Do not mutate another conversation');
    }
    const normal = enforceExecutionPolicy({ tools: [] }, config);
    assert.equal(normal.config, config, 'Empty tool declarations alone do not disable authorized delegation');
    protocols.add(model.api); checked++;
  }
  assert.ok(checked > 1000);
  assert.ok(protocols.size >= 5);
});

test('invalid execution permissions fail closed before provider execution', () => {
  for (const executionPolicy of [false, {}, { allowsClientTools: 'false', allowsSubagents: true }]) {
    assert.throws(() => enforceExecutionPolicy({ executionPolicy }, {}), { code: 'execution_policy_invalid' });
  }
});

test('authentication diagnostics keep only allowlisted codes and numeric status', () => {
  for (const error of [new SyntaxError('NEW-SECRET'), Object.assign(new Error('NEW-SECRET'), { code: 'NEW-SECRET', cause: { body: 'NEW-SECRET' } })]) {
    const safe = authFailure(error);
    assert.equal(safe.code, 'oauth_request_failed');
    assert.ok(!JSON.stringify(safe).includes('NEW-SECRET'));
    assert.ok(!safe.message.includes('NEW-SECRET'));
    assert.equal(safe.cause, undefined);
  }
  const safe = authFailure({ code: 'invalid_grant', message: 'SECRET', statusCode: 401 });
  assert.equal(safe.code, 'invalid_grant');assert.equal(safe.statusCode, 401);
});

test('revocation waits for an in-flight rotation without blocking another provider', async () => {
  const operations = new OAuthOperations();
  const events = [];
  let finishRefresh;
  const refresh = operations.run('xai', async () => { await new Promise(resolve => { finishRefresh = resolve; }); events.push('rotated'); });
  await Promise.resolve();
  const revoke = operations.run('xai', () => events.push('revoked'));
  await operations.run('openai', () => events.push('other-provider'));
  assert.deepEqual(events, ['other-provider']);
  finishRefresh(); await Promise.all([refresh, revoke]);
  assert.deepEqual(events, ['other-provider', 'rotated', 'revoked']);
  await assert.rejects(operations.run('xai', () => { throw new Error('failed'); }));
  await operations.run('xai', () => events.push('recovered'));
  assert.equal(events.at(-1), 'recovered');
});
