// Real filesystem/HTTP regression tests; not target-machine acceptance.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createRequire } from 'node:module';
import { mkdtemp, mkdir, writeFile, appendFile, rename, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import http from 'node:http';
const { redact, createLogger, LogTail, logFiles, consumeLine, loopback, readJsonResponse, startDiagnostics } = createRequire(import.meta.url)('../vscode-startup/diagnostics.cjs');
const temporary = async action => { const root = await mkdtemp(path.join(tmpdir(), 'lokiente-diagnostics-')); try { return await action(root); } finally { await rm(root, { recursive: true, force: true }); } };
test('unified output redacts known secrets and credential formats and reveals errors', () => {
    const lines = []; let shown = 0;
    const logger = createLogger({ info: v => lines.push(v), error: v => lines.push(v), show: () => shown++ }, ['synthetic-secret']);
    logger.info('Kilo Code', 'ready synthetic-secret Bearer abc123 api_key="hidden" https://localhost/?token=hidden');
    logger.error('LM Studio', 'failed');
    assert.equal(shown, 1); assert.ok(lines[0].includes('[Kilo Code]')); assert.doesNotMatch(lines[0], /synthetic-secret|abc123|hidden/);
    assert.doesNotMatch(redact('Authorization: Basic YWxhZGRpbjpvcGVuc2VzYW1l'), /YWxh/);
});
test('router logs forward metadata and never prompts or raw completions', () => {
    const values = []; const logger = { info: (...v) => values.push(v), error: (...v) => values.push(v), warn: (...v) => values.push(v) };
    consumeLine(logger, 'Router', JSON.stringify({ event: 'request_failed', code: 'model_load_failed', prompt: 'private-prompt', completion: 'private-answer' }));
    consumeLine(logger, 'Kilo Code', JSON.stringify({ type: 'text', part: { text: 'private-answer' } }));
    consumeLine(logger, 'Kilo Code', JSON.stringify({ level: 'INFO', message: 'server started' }));
    consumeLine(logger, 'LM Studio', '[DEBUG] private-answer');
    assert.equal(values.length, 2); assert.doesNotMatch(JSON.stringify(values), /private-/); assert.match(JSON.stringify(values), /model_load_failed|server started/);
});

test('historical errors retain their severity label without becoming new live errors', () => {
    const values = [];
    const logger = Object.fromEntries(['info', 'warn', 'error'].map(level => [level, (component, message) => values.push({ level, component, message })]));
    consumeLine(logger, 'LM Studio', '[2026-01-01 10:00:00][ERROR] old load failed', { historical: true });
    consumeLine(logger, 'LM Studio', '[2026-01-01 10:00:01][ERROR] current load failed');
    assert.equal(values[0].level, 'info'); assert.match(values[0].message, /history ERROR.*old load failed/);
    assert.equal(values[1].level, 'error'); assert.match(values[1].message, /current load failed/);
});
test('tail handles missing files, partial UTF8, truncation and rotation', async () => temporary(async root => {
    const file = path.join(root, 'actual.log'), lines = [], tail = new LogTail(file, v => lines.push(v));
    await tail.read();
    const bytes = Buffer.from('Grüße\n'); await writeFile(file, bytes.subarray(0, 3)); await tail.read(); assert.equal(lines.length, 0);
    await appendFile(file, bytes.subarray(3)); await tail.read(); assert.deepEqual(lines, ['Grüße']);
    await writeFile(file, 'x\n'); await tail.read(); assert.equal(lines.at(-1), 'x');
    await rename(file, file + '.old'); await writeFile(file, 'rotated\n'); await tail.read(); assert.equal(lines.at(-1), 'rotated');
}));
test('replay and line length are bounded; own output cannot feed itself', async () => temporary(async root => {
    const file = path.join(root, 'one.log'), lines = [];
    await writeFile(file, 'old\n' + 'a'.repeat(80) + '\nnew\n');
    await new LogTail(file, v => lines.push(v), { replayBytes: 20 }).read(); assert.deepEqual(lines, ['new']);
    await writeFile(path.join(root, '1-LoKiEnte.log'), 'feedback\n');
    assert.deepEqual((await logFiles(root)).map(v => path.basename(v)), ['one.log']);
}));
test('HTTP diagnostics reject public URLs, invalid JSON and oversized data', async () => {
    assert.throws(() => loopback('http://example.com/v1'), /loopback/); assert.throws(() => loopback('http://user:password@localhost/'), /loopback/);
    let mode = 'valid';
    const server = http.createServer((req, res) => { res.end(mode === 'valid' ? '{"data":[]}' : mode === 'invalid' ? 'bad' : 'x'.repeat(2 * 1024 * 1024 + 1)); });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try { const url = `http://127.0.0.1:${server.address().port}/models`; assert.deepEqual(await readJsonResponse(url), { data: [] });
        mode = 'invalid'; await assert.rejects(readJsonResponse(url)); mode = 'large'; await assert.rejects(readJsonResponse(url), /size limit/);
    } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});
test('managed monitor logs real connection failure and recovery once per transition', async () => temporary(async root => {
    let healthy = true; const values = [];
    const server = http.createServer((req, res) => { res.writeHead(healthy ? 200 : 503); res.end(JSON.stringify({ data: [] })); });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const data = path.join(root, 'vscode-data'); await mkdir(path.join(data, 'logs'), { recursive: true });
    await writeFile(path.join(data, 'logs', 'exthost.log'), '[2020-01-01 00:00:00][INFO] actual managed host started\n[2020-01-01 00:00:01][ERROR] managed failure\n');
    await writeFile(path.join(data, 'logs', 'renderer.log'), `${new Date().toISOString()} [error] current startup error\n`);
    const logger = Object.fromEntries(['info', 'warn', 'error'].map(level => [level, (component, message) => values.push({ level, component, message })]));
    const monitor = startDiagnostics({ root, dataDirectory: data, logger, intervalMs: 100000,
        env: { LOKIENTE_LOG_SINCE_UTC: new Date(Date.now() - 30000).toISOString(), KILO_CONFIG_CONTENT: JSON.stringify({ provider: { lmstudio: { options: { baseURL: `http://127.0.0.1:${server.address().port}/v1` } } } }) } });
    try {
        await monitor.ready; const initial = values.length; await monitor.poll(); assert.equal(values.length, initial);
        healthy = false; await monitor.poll(); assert.ok(values.some(v => v.level === 'error' && /HTTP 503/.test(v.message)));
        healthy = true; await monitor.poll(); assert.equal(values.filter(v => /catalog is readable/.test(v.message)).length, 2);
        assert.ok(values.some(v => /managed failure/.test(v.message))); assert.ok(!values.some(v => /inference.*passed/i.test(v.message)));
        assert.ok(values.some(v => v.level === 'info' && /history ERROR.*managed failure/.test(v.message)));
        assert.ok(values.some(v => v.level === 'error' && /current startup error/.test(v.message) && !/history/.test(v.message)));
        await appendFile(path.join(data, 'logs', 'exthost.log'), '[ERROR] new host failure\n'); await monitor.poll();
        assert.ok(values.some(v => v.level === 'error' && /new host failure/.test(v.message)));
    } finally { monitor.dispose(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
}));
