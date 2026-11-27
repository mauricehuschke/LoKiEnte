// Regression tests for evidence handling. These do NOT prove a live toolchain.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createRequire } from 'node:module';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
const { runNative, inspectKiloEvents, summarize, junit, checkToolchain, withDeadline, waitForWorkspaceTrust } = createRequire(import.meta.url)('../vscode-startup/toolchain-check.cjs');
const marker = 'LOKIENTE_ACCEPTANCE_' + 'a'.repeat(32), file = path.resolve('synthetic-probe.txt');
const events = [
    { type: 'tool_use', part: { tool: 'read', state: { status: 'completed', input: { filePath: file }, output: marker } } },
    { type: 'text', part: { text: marker } }, { type: 'step_finish', part: { reason: 'stop' } },
];
const inspect = value => inspectKiloEvents(value.map(e => JSON.stringify(e)).join('\n'), marker, file);
test('fresh test profile waits for explicit Workspace Trust instead of failing before the user can answer', async () => {
    let grant, disposed = false, prompts = 0;
    const workspace = { isTrusted: false, onDidGrantWorkspaceTrust(fn) { grant = fn; return { dispose() { disposed = true; } }; } };
    const pending = waitForWorkspaceTrust({ workspace, window: { async showWarningMessage() { prompts++; } } }, { warn() {} }, 1000);
    assert.equal(workspace.isTrusted, false); workspace.isTrusted = true; grant(); await pending;
    assert.equal(prompts, 1); assert.equal(disposed, true);
});
test('missing Workspace Trust blocks acceptance without changing trust policy', async () => {
    let disposed = false;
    const workspace = { isTrusted: false, onDidGrantWorkspaceTrust() { return { dispose() { disposed = true; } }; } };
    await assert.rejects(waitForWorkspaceTrust({ workspace, window: { async showWarningMessage() {} } }, { warn() {} }, 20), error => error.blocked === true);
    assert.equal(workspace.isTrusted, false); assert.equal(disposed, true);
});
test('a completed tool result and completed final answer are both required', () => {
    assert.deepEqual(inspect(events), { read: true, replyMatches: true, finished: true, error: false });
    assert.equal(inspect(events.slice(1)).read, false);
    assert.equal(inspect(events.slice(0, 2)).finished, false);
    assert.equal(inspect([events[0], { type: 'text', part: { text: 'wrong' } }, events[2]]).replyMatches, false);
    const wrong = structuredClone(events); wrong[0].part.state.input.filePath += '.other'; assert.equal(inspect(wrong).read, false);
    wrong[0].part.state.input.filePath = file; wrong[0].part.state.output = 'wrong'; assert.equal(inspect(wrong).read, false);
    assert.equal(inspect([...events, { type: 'error' }]).error, true);
    assert.throws(() => inspectKiloEvents('{"type":', marker, file));
});
test('missing, skipped, failed and blocked evidence never produces PASS', () => {
    assert.equal(summarize([], ['real-host']), 'BLOCKED');
    for (const status of ['SKIPPED', 'BLOCKED', 'NOT_APPLICABLE']) assert.equal(summarize([{ id: 'a', status }], ['a']), 'BLOCKED');
    assert.equal(summarize([{ id: 'a', status: 'FAIL' }], ['a']), 'FAIL');
    assert.equal(summarize([{ id: 'a', status: 'PASS' }, { id: 'optional', status: 'NOT_APPLICABLE' }], ['a']), 'PASS');
});
test('JUnit escapes errors and records blocked checks as skipped', () => {
    const xml = junit({ cases: [{ id: 'a', component: 'Kilo', status: 'FAIL', evidence: '<bad & "quoted">' }, { id: 'b', status: 'BLOCKED', evidence: 'unavailable' }] });
    assert.match(xml, /failures="1" skipped="1"/); assert.match(xml, /&lt;bad &amp; &quot;quoted&quot;&gt;/); assert.match(xml, /<skipped/);
});
test('real subprocess results include nonzero exit and stderr', async () => {
    const result = await runNative(process.execPath, ['-e', 'process.stdout.write("actual");process.stderr.write("error");process.exitCode=7']);
    assert.deepEqual(result, { code: 7, stdout: 'actual', stderr: 'error' });
    await assert.rejects(runNative(path.join(tmpdir(), 'missing-lokiente-executable'), []), /Cannot start/);
});
test('native deadline also covers inherited open pipes after parent exit', async () => {
    const script = 'require("node:child_process").spawn(process.execPath,["-e","setTimeout(()=>{},10000)"],{detached:true,stdio:["ignore",process.stdout,process.stderr]}).unref();process.exit(0)';
    const start = Date.now();
    await assert.rejects(runNative(process.execPath, ['-e', script], { timeoutMs: 3000 }), error => error.code === 'LOKIENTE_NATIVE_TIMEOUT' && error.processExited === true);
    assert.ok(Date.now() - start < 8000);
});
test('activation deadline fails instead of hanging indefinitely', async () => {
    const keepAlive = setInterval(() => {}, 100);
    try { await assert.rejects(withDeadline(() => new Promise(() => {}), 20, 'activation timeout'), /activation timeout/);
        assert.equal(await withDeadline(async () => 42, 100, 'timeout'), 42);
    } finally { clearInterval(keepAlive); }
});
test('outside the real Electron host the live runner records BLOCKED and no inference', async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'lokiente-host-evidence-'));
    try {
        let queried = false;
        const report = await checkToolchain({ root, interactive: false, env: {}, logger: { info() {}, warn() {}, error() {} },
            vscode: { version: 'synthetic', env: { appHost: 'web' }, get extensions() { queried = true; throw new Error('Must not run'); } } });
        assert.equal(report.status, 'BLOCKED'); assert.equal(queried, false);
        for (const id of report.required) assert.ok(report.cases.some(c => c.id === id && c.status === 'BLOCKED'));
        assert.equal(JSON.parse(await readFile(report.reportPath, 'utf8')).status, 'BLOCKED');
        assert.match(await readFile(report.reportPath.replace('.json', '.junit.xml'), 'utf8'), /skipped=/);
    } finally { await rm(root, { recursive: true, force: true }); }
});
