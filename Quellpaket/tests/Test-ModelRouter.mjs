import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { mkdtemp, writeFile, copyFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createModelRouter, makePowerShellSwitcher, validatePool } from '../ModelRouter.mjs';

test('high and fast routes select distinct local models, including a deferred profile', async () => {
  const received = [];
  const backend = http.createServer(async (req, res) => {
    let data = '';
    for await (const chunk of req) data += chunk;
    received.push(JSON.parse(data).model);
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ choices: [{ message: { role: 'assistant', content: 'ok' } }] }));
  });

  backend.listen(0, '127.0.0.1');
  await once(backend, 'listening');
  const profiles = ['coder-high', 'coder-fast', 'review', 'fast'].map(alias => ({
    Alias: alias, RouteId: `shadow-${alias}`, InstanceId: `owned-${alias}`,
    ContextLength: 16384, OutputLimit: 4096,
    SmokeTests: { Chat: 'Passed', ToolCall: 'Passed', ToolResultRoundTrip: 'Passed' },
  }));
  profiles[0].VerificationState = 'Deferred';
  profiles[0].SmokeTests = { Chat: 'NotRun', ToolCall: 'NotRun', ToolResultRoundTrip: 'NotRun' };
  const switched = [];
  const router = createModelRouter({
    config: { SchemaVersion: 2, Status: 'Ready', Profiles: profiles,
      BackendApiBaseUrl: `http://127.0.0.1:${backend.address().port}/v1` },
    configDigest: 'fixture',
    switchModel: async profile => {
      switched.push(profile.Alias);
      return { Status: 'Ready', Alias: profile.Alias, ModelId: profile.InstanceId,
        ContextLength: profile.ContextLength, Parallel: 1, VerificationState: 'Verified' };
    },
  });

  router.listen(0, '127.0.0.1');
  await once(router, 'listening');
  const base = `http://127.0.0.1:${router.address().port}`;
  try {
    const models = await (await fetch(`${base}/v1/models`)).json();
    assert.deepEqual(models.data.map(model => model.id),
      ['shadow-coder-high', 'shadow-coder-fast', 'shadow-review', 'shadow-fast']);
    const initialHealth = await (await fetch(`${base}/health`)).json();
    assert.equal(initialHealth.models[0].verification, 'Deferred');
    for (const model of ['shadow-coder-high', 'shadow-coder-fast']) {
      const response = await fetch(`${base}/v1/chat/completions`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ model, messages: [{ role: 'user', content: 'fixture' }] }),
      });
      assert.equal(response.status, 200);
      assert.equal((await response.json()).choices[0].message.content, 'ok');
    }
    assert.deepEqual(switched, ['coder-high', 'coder-fast']);
    assert.deepEqual(received, ['owned-coder-high', 'owned-coder-fast']);
    const finalHealth = await (await fetch(`${base}/health`)).json();
    assert.equal(finalHealth.models[0].verification, 'Verified');
    const old = await fetch(`${base}/v1/chat/completions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ model: 'shadow-coder', messages: [{ role: 'user', content: 'fixture' }] }),
    });
    assert.equal(old.status, 400);
  } finally {
    router.close();
    backend.close();
    await Promise.all([once(router, 'close'), once(backend, 'close')]);
  }
});

test('only explicitly deferred profiles may lack successful smoke tests', () => {
  const profile = { Alias: 'coder-high', RouteId: 'shadow-coder-high', InstanceId: 'owned-high',
    ContextLength: 16384, OutputLimit: 4096, VerificationState: 'Deferred',
    SmokeTests: { Chat: 'NotRun', ToolCall: 'NotRun', ToolResultRoundTrip: 'NotRun' } };
  const review = { ...profile, Alias: 'review', RouteId: 'shadow-review', InstanceId: 'owned-review',
    VerificationState: 'Verified', SmokeTests: { Chat: 'Passed', ToolCall: 'Passed', ToolResultRoundTrip: 'Passed' } };
  const config = { SchemaVersion: 2, Status: 'Ready', BackendApiBaseUrl: 'http://127.0.0.1:1234/v1',
    Profiles: [profile, review] };
  assert.equal(validatePool(config).profiles.has('shadow-coder-high'), true);
  const failedTest = { ...profile, SmokeTests: { Chat: 'NotVerified', ToolCall: 'NotVerified', ToolResultRoundTrip: 'NotVerified' } };
  assert.equal(validatePool({ ...config, Profiles: [failedTest, review] }).profiles.has('shadow-coder-high'), true);
  assert.throws(() => validatePool({ ...config, Profiles: [{ ...profile,
    SmokeTests: { Chat: 'Passed', ToolCall: 'NotRun', ToolResultRoundTrip: 'NotRun' } }, review] }),
  /explicitly deferred smoke tests/);
});

test('resource refusal is reported explicitly by the real controller process', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'shadow-router-fit-'));
  const script = path.join(root, 'Switch-LocalModel.ps1');
  try {
    await copyFile(fileURLToPath(new URL('../Switch-LocalModel.ps1', import.meta.url)), script);
    await writeFile(path.join(root, 'ModelPool.ps1'), `function Switch-ShadowLocalModel {\n` +
      `param($InstallRoot,$Alias)\n$error=[InvalidOperationException]::new('synthetic')\n` +
      `if($Alias -eq 'coder-fast'){$error.Data['ShadowModelVerificationFailure']=$true}` +
      `else{$error.Data['ShadowResourceFitFailure']=$true}\nthrow $error\n}\n`);
    const switcher = makePowerShellSwitcher({ installRoot: root, pwsh: 'pwsh.exe', switchScript: script });
    await assert.rejects(() => switcher({ Alias: 'coder-high' }),
      error => error.code === 'model_memory_unavailable' && error.status === 503 &&
        error.message.includes('Modelldatei bleibt erhalten'));
    await assert.rejects(() => switcher({ Alias: 'coder-fast' }),
      error => error.code === 'model_unverified' && error.status === 503 &&
        error.message.includes('Werkzeugtest'));
    const profiles = ['coder-high', 'review'].map(alias => ({
      Alias: alias, RouteId: `shadow-${alias}`, InstanceId: `owned-${alias}`,
      ContextLength: 16384, OutputLimit: 4096,
      SmokeTests: { Chat: 'Passed', ToolCall: 'Passed', ToolResultRoundTrip: 'Passed' },
    }));
    const router = createModelRouter({ config: { SchemaVersion: 2, Status: 'Ready',
      BackendApiBaseUrl: 'http://127.0.0.1:1234/v1', Profiles: profiles },
    configDigest: 'fixture', switchModel: switcher });
    router.listen(0, '127.0.0.1');
    await once(router, 'listening');
    try {
      const base = `http://127.0.0.1:${router.address().port}`;
      const response = await fetch(`${base}/v1/chat/completions`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ model: 'shadow-coder-high', messages: [{ role: 'user', content: 'fixture' }] }),
      });
      assert.equal(response.status, 503);
      assert.equal((await response.json()).error.code, 'model_memory_unavailable');
      const health = await (await fetch(`${base}/health`)).json();
      assert.equal(health.models[0].verification, 'Deferred');
    } finally {
      router.close();
      await once(router, 'close');
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
