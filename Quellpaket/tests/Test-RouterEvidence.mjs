// Synthetic backend regression: validates evidence correlation, not real inference.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { createHash } from 'node:crypto';
import { createModelRouter } from '../ModelRouter.mjs';
for (const mode of ['json', 'sse', 'incomplete', 'wrong-answer', 'upstream-error']) test(`router acceptance metadata: ${mode}`, async () => {
    const marker = 'LOKIENTE_ACCEPTANCE_' + 'e'.repeat(32), logs = [];
    const backend = http.createServer((req, res) => {
        if (mode === 'upstream-error') { res.writeHead(500); res.end('private-error'); return; }
        if (['sse', 'incomplete'].includes(mode)) {
            res.writeHead(200, { 'content-type': 'text/event-stream' });
            for (const content of [marker.slice(0, 24), marker.slice(24)]) res.write(`data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\n`);
            res.end(mode === 'sse' ? 'data: [DONE]\n\n' : '');
        } else { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify({ choices: [{ message: { content: mode === 'wrong-answer' ? 'other' : marker } }] })); }
    });
    backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
    const profiles = ['coder', 'review'].map(Alias => ({ Alias, RouteId: 'shadow-' + Alias, InstanceId: 'owned-' + Alias, ContextLength: 8192, OutputLimit: 1024,
        SmokeTests: { Chat: 'Passed', ToolCall: 'Passed', ToolResultRoundTrip: 'Passed' } }));
    const router = createModelRouter({ config: { SchemaVersion: 2, Status: 'Ready', Profiles: profiles, BackendApiBaseUrl: `http://127.0.0.1:${backend.address().port}/v1` },
        configDigest: 'synthetic', log: entry => logs.push(entry),
        switchModel: async profile => ({ Status: 'Ready', Alias: profile.Alias, ModelId: profile.InstanceId, ContextLength: 8192, Parallel: 1, VerificationState: 'Verified' }) });
    router.listen(0, '127.0.0.1'); await once(router, 'listening');
    try {
        const response = await fetch(`http://127.0.0.1:${router.address().port}/v1/chat/completions`, { method: 'POST', headers: { 'content-type': 'application/json' },
            body: JSON.stringify({ model: 'shadow-coder', stream: ['sse', 'incomplete'].includes(mode), messages: [{ role: 'user', content: marker }] }) });
        await response.text().catch(() => {});
        const complete = logs.find(v => v.event === 'request_completed'), failed = logs.find(v => v.event === 'request_failed');
        if (['incomplete', 'upstream-error'].includes(mode)) { assert.equal(complete, undefined); assert.ok(failed); }
        else { assert.equal(complete?.probeReplyMatched, mode !== 'wrong-answer'); assert.equal(complete?.modelId, 'owned-coder'); }
        const event = complete || failed;
        assert.equal(event.probeHash, createHash('sha256').update(marker).digest('hex'));
        assert.equal(event.requestId, logs.find(v => v.event === 'model_switch_started').requestId);
        assert.doesNotMatch(JSON.stringify(logs), new RegExp(marker + '|private-error'));
    } finally {
        router.closeAllConnections(); await new Promise(resolve => router.close(resolve));
        backend.closeAllConnections(); await new Promise(resolve => backend.close(resolve));
    }
});
