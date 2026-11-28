// Real router/HTTP/filesystem regressions; the Kilo UI/model boundary is synthetic.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, writeFile, appendFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import http from 'node:http';
import { once } from 'node:events';
import { createModelRouter } from '../ModelRouter.mjs';
const { waitForWebviewExchange } = createRequire(import.meta.url)('../vscode-startup/toolchain-check.cjs');
const marker = 'LOKIENTE_ACCEPTANCE_' + 'c'.repeat(32), probeHash = createHash('sha256').update(marker).digest('hex');
async function temporary(action) {
    const root = await mkdtemp(path.join(tmpdir(), 'lokiente-webview-'));
    try { return await action(root); }
    finally { assert.ok(path.resolve(root).startsWith(path.resolve(tmpdir()) + path.sep)); await rm(root, { recursive: true, force: true }); }
}

for (const content of ['trailing-user-context', 'text-parts', 'tool-followup', 'nonuser-only']) test(`real HTTP webview correlation: ${content}`, () => temporary(async root => {
    const logs = [], file = path.join(root, 'router.jsonl');
    const backend = http.createServer((req, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify({ choices: [{ message: { content: marker } }] })); });
    backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
    const profile = { Alias: 'coder', RouteId: 'shadow-coder', InstanceId: 'owned-coder', ContextLength: 8192, OutputLimit: 1024,
        SmokeTests: { Chat: 'Passed', ToolCall: 'Passed', ToolResultRoundTrip: 'Passed' } };
    const alternate = { ...profile, Alias: 'review', RouteId: 'shadow-review', InstanceId: 'owned-review' };
    let router;
    try {
        router = createModelRouter({ config: { SchemaVersion: 2, Status: 'Ready', Profiles: [profile, alternate], BackendApiBaseUrl: `http://127.0.0.1:${backend.address().port}/v1` },
            configDigest: 'synthetic', log: event => logs.push(event), switchModel: async () => ({ Status: 'Ready', Alias: profile.Alias, ModelId: profile.InstanceId, ContextLength: 8192, Parallel: 1, VerificationState: 'Verified' }) });
        router.listen(0, '127.0.0.1'); await once(router, 'listening');
        const text = content === 'text-parts' ? [{ type: 'text', text: marker }, { type: 'image_url', image_url: { url: 'synthetic-not-sent-elsewhere' } }] : marker;
        const messages = content === 'nonuser-only'
            ? [{ role: 'system', content: marker }, { role: 'assistant', content: marker }, { role: 'tool', content: marker }, { role: 'user', content: 'No nonce in actual user messages' }]
            : [{ role: 'assistant', content: 'LOKIENTE_ACCEPTANCE_' + 'a'.repeat(32) }, { role: 'user', content: text }];
        if (content === 'tool-followup') messages.push({ role: 'assistant', content: 'Read completed' }, { role: 'tool', tool_call_id: 'synthetic', content: 'private tool result' });
        messages.push({ role: 'user', content: '<environment_details>Editor state without the nonce</environment_details>' });
        const response = await fetch(`http://127.0.0.1:${router.address().port}/v1/chat/completions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ model: profile.RouteId, messages }) });
        assert.equal(response.status, 200); await response.json();
        await writeFile(file, logs.map(event => JSON.stringify(event)).join('\n') + '\n');
        const evidence = {};
        if (content === 'nonuser-only') {
            assert.equal(logs.find(event => event.event === 'request_completed').probeHash, undefined);
            await assert.rejects(waitForWebviewExchange({ file, probeHash, evidence, timeoutMs: 200, requestTimeoutMs: 20, pollMs: 5 }), error => error.code === 'KILO_WEBVIEW_REQUEST_NOT_OBSERVED');
            return;
        }
        await waitForWebviewExchange({ file, probeHash, evidence, timeoutMs: 1000, requestTimeoutMs: 100, pollMs: 5 });
        assert.equal(evidence.stage, 'completed'); assert.equal(evidence.requestObserved, true); assert.equal(evidence.replyMatched, true);
        assert.ok(evidence.events.some(event => event.event === 'request_received'));
        assert.equal(logs.find(event => event.event === 'request_completed').probeHash, probeHash);
        assert.doesNotMatch(JSON.stringify(logs) + JSON.stringify(evidence), /private tool result|environment_details|LOKIENTE_ACCEPTANCE_/);
    } finally { router?.closeAllConnections(); backend.closeAllConnections(); await Promise.all([router?.listening ? new Promise(resolve => router.close(resolve)) : Promise.resolve(), new Promise(resolve => backend.close(resolve))]); }
}));

test('unknown nonces and unrelated requests cannot prove webview success', () => temporary(async root => {
    const file = path.join(root, 'router.jsonl'), evidence = {};
    await writeFile(file, JSON.stringify({ event: 'request_completed', probeHash: 'd'.repeat(64), probeReplyMatched: true }) + '\n');
    await assert.rejects(waitForWebviewExchange({ file, probeHash, evidence, timeoutMs: 200, requestTimeoutMs: 20, pollMs: 5 }), error => error.code === 'KILO_WEBVIEW_REQUEST_NOT_OBSERVED');
    assert.equal(evidence.requestObserved, undefined); assert.equal(evidence.replyMatched, undefined); assert.equal(evidence.unmatchedEvents, 1);
    await assert.rejects(waitForWebviewExchange({ file, evidence: {} }), /valid nonce hash/);
}));

test('started requests and wrong answers retain distinct failure evidence without being accepted', () => temporary(async root => {
    const file = path.join(root, 'router.jsonl');
    for (const completed of [false, true]) {
        const evidence = {};
        await writeFile(file, JSON.stringify({ event: 'model_switch_started', probeHash, requestId: 'r', alias: 'coder' }) + '\n' +
            (completed ? JSON.stringify({ event: 'request_completed', probeHash, requestId: 'r', probeReplyMatched: false }) + '\n' : ''));
        await assert.rejects(waitForWebviewExchange({ file, probeHash, evidence, timeoutMs: 30, requestTimeoutMs: 10, pollMs: 5 }), error => error.code === 'KILO_WEBVIEW_RESPONSE_NOT_VERIFIED');
        assert.equal(evidence.stage, completed ? 'completed-without-marker' : 'response-not-completed'); assert.equal(evidence.requestObserved, true);
    }
}));

test('a correlated request failure and a timeout are reported immediately with their code', () => temporary(async root => {
    const file = path.join(root, 'router.jsonl');
    for (const event of ['request_failed', 'request_timed_out']) {
        const evidence = {};
        await writeFile(file, JSON.stringify({ event, probeHash, requestId: 'r', code: 'synthetic_failure' }) + '\n');
        await assert.rejects(waitForWebviewExchange({ file, probeHash, evidence, timeoutMs: 1000, pollMs: 5 }), error => error.code === 'KILO_WEBVIEW_ROUTER_FAILED');
        assert.equal(evidence.stage, 'router-request-failed'); assert.equal(evidence.failureCode, 'synthetic_failure');
    }
}));

test('partial/late router evidence is persisted before completion and cancellation cannot become PASS', () => temporary(async root => {
    const file = path.join(root, 'router.jsonl'), evidence = {}, stages = [], controller = new AbortController();
    await writeFile(file, JSON.stringify({ event: 'request_received', probeHash, requestId: 'r' }) + '\n');
    const pending = waitForWebviewExchange({ file, probeHash, evidence, signal: controller.signal, timeoutMs: 1000, pollMs: 5, onUpdate: async value => {
        stages.push(value.stage);
        if (value.stage === 'request-received') await appendFile(file, JSON.stringify({ event: 'request_completed', probeHash, requestId: 'r', probeReplyMatched: true }) + '\n');
        if (value.stage === 'completed') controller.abort(new Error('synthetic window closed'));
    } });
    await assert.rejects(pending, error => error.code === 'LOKIENTE_ACCEPTANCE_CANCELLED');
    assert.deepEqual(stages, ['request-received', 'completed']);
}));
