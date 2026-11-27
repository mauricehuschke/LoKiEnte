// Regression tests for evidence handling. These do NOT prove a live toolchain.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createRequire } from 'node:module';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import vm from 'node:vm';
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

test('trust guidance opens the supported management UI and waits for the user grant', async () => {
    let grant, opened = false;
    const workspace = { isTrusted: false, onDidGrantWorkspaceTrust(fn) { grant = fn; return { dispose() {} }; } };
    const pending = waitForWorkspaceTrust({ workspace,
        window: { async showWarningMessage(message, ...actions) { assert.ok(actions.includes('Manage Workspace Trust')); return 'Manage Workspace Trust'; } },
        commands: { async executeCommand(id) { assert.equal(id, 'workbench.trust.manage'); opened = true; } },
    }, { warn() {} }, 1000);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(opened, true); assert.equal(workspace.isTrusted, false);
    workspace.isTrusted = true; grant(); await pending;
});

test('cancelling the trust prompt blocks without a grant or policy change', async () => {
    let disposed = false;
    const workspace = { isTrusted: false, onDidGrantWorkspaceTrust() { return { dispose() { disposed = true; } }; } };
    await assert.rejects(waitForWorkspaceTrust({ workspace, window: { async showWarningMessage() { return 'Cancel acceptance'; } } },
        { warn() {} }, 1000), error => error.blocked === true && /cancelled/.test(error.message));
    assert.equal(disposed, true); assert.equal(workspace.isTrusted, false);
});
test('closing/cancelling a trust wait disposes the listener and cannot grant trust', async () => {
    const controller = new AbortController(); let disposed = false;
    const workspace = { isTrusted: false, onDidGrantWorkspaceTrust() { return { dispose() { disposed = true; } }; } };
    const pending = waitForWorkspaceTrust({ workspace, window: { async showWarningMessage() {} } }, { warn() {} }, 1000, controller.signal);
    controller.abort(new Error('synthetic window closed'));
    await assert.rejects(pending, error => error.blocked && error.code === 'LOKIENTE_ACCEPTANCE_CANCELLED');
    assert.equal(disposed, true); assert.equal(workspace.isTrusted, false);
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
test('cancelling acceptance terminates its real native child and preserves command evidence', async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'lokiente-cancel-native-')), ready = path.join(root, 'ready'), later = path.join(root, 'later');
    try {
        const controller = new AbortController();
        const pending = runNative(process.execPath, ['-e', 'const fs=require("node:fs");fs.writeFileSync(process.argv[1],"ready");process.stdout.write("started");setTimeout(()=>fs.writeFileSync(process.argv[2],"must not happen"),700)', ready, later], { signal: controller.signal });
        const assertion = assert.rejects(pending, error => error.code === 'LOKIENTE_ACCEPTANCE_CANCELLED' && error.blocked && !!error.nativeResult);
        const start = Date.now();
        while (Date.now() - start < 5000) { try { await readFile(ready); break; } catch { await new Promise(resolve => setTimeout(resolve, 10)); } }
        assert.equal(await readFile(ready, 'utf8'), 'ready'); controller.abort(new Error('synthetic acceptance cancelled')); await assertion;
        await new Promise(resolve => setTimeout(resolve, 850));
        await assert.rejects(readFile(later), error => error.code === 'ENOENT');
    } finally { await rm(root, { recursive: true, force: true }); }
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

test('acceptance itself waits for delayed Kilo discovery before activating, with bounded mocked host boundaries', async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'lokiente-acceptance-discovery-'));
    try {
        const require = createRequire(import.meta.url), realRequire = createRequire(new URL('../vscode-startup/toolchain-check.cjs', import.meta.url));
        const source = await readFile(new URL('../vscode-startup/toolchain-check.cjs', import.meta.url), 'utf8');
        const helperSource = path.join(root, 'app', 'vscode-startup'); await mkdir(helperSource, { recursive: true });
        for (const file of ['extension.cjs', 'diagnostics.cjs', 'toolchain-check.cjs', 'kilo-startup.cjs', 'acceptance-project.cjs', 'acceptance-lifecycle.cjs', 'acceptance-configuration.cjs']) {
            await writeFile(path.join(helperSource, file), await readFile(new URL('../vscode-startup/' + file, import.meta.url)));
        }
        const installed = path.join(root, 'vscode-extensions', 'kilocode.kilo-code-synthetic'); await mkdir(installed, { recursive: true });
        await writeFile(path.join(installed, 'package.json'), JSON.stringify({ publisher: 'kilocode', name: 'kilo-code', version: 'synthetic' }));
        await writeFile(path.join(root, 'toolchain.json'), '{}');
        let visible = false, activations = 0, hanging = false, configurationFailure = false;
        const kilo = { extensionPath: installed, async activate() {
            activations++;
            const snapshot = JSON.parse(await readFile(path.join(root, 'diagnostics', 'toolchain', 'a'.repeat(32), 'acceptance.json'), 'utf8'));
            assert.equal(snapshot.status, 'RUNNING');
            assert.equal(snapshot.progress.at(-1).id, 'kilo-activation'); assert.equal(snapshot.progress.at(-1).status, 'RUNNING');
            assert.ok(snapshot.progress.some(event => event.id === 'production-configuration' && event.status === 'PASS'));
            if (hanging) await new Promise(() => {});
            throw new Error('SYNTHETIC_STOP_BEFORE_NATIVE_OR_INFERENCE');
        } };
        const sandbox = { module: { exports: {} }, __dirname: path.resolve('Quellpaket/vscode-startup'), setTimeout, clearTimeout, setInterval, clearInterval, AbortController,
            process: { versions: { electron: 'synthetic', node: process.versions.node } },
            require(id) {
                if (id === './acceptance-project.cjs') return { prepareAcceptanceProject: async () => ({ project: path.join(root, 'diagnostics', 'toolchain', 'a'.repeat(32), 'project'), head: 'b'.repeat(40) }) };
                if (id === './acceptance-configuration.cjs') return { verifyAcceptanceConfiguration: async ({ evidence }) => {
                    if (configurationFailure) {
                        evidence.settingsChanges = [{ key: 'editor.fontSize', change: 'modified' }];
                        throw new Error('Synthetic production configuration mismatch: editor.fontSize');
                    }
                    return { boundary: 'synthetic only' };
                } };
                if (id === './kilo-startup.cjs') { const real = realRequire(id); return { ...real, waitForKilo: args => real.waitForKilo({ ...args, timeoutMs: 1000, pollMs: 5 }) }; }
                return realRequire(id);
            } };
        vm.runInNewContext(source, sandbox);
        const timer = setTimeout(() => { visible = true; }, 80);
        const options = { root, runId: 'a'.repeat(32), interactive: false,
            env: { KILO_CONFIG_CONTENT: JSON.stringify({ enabled_providers: ['lmstudio'], provider: { lmstudio: { options: { baseURL: 'http://127.0.0.1:1234/v1' }, models: { fast: { id: 'synthetic' } } } } }) },
            logger: { info() {}, warn() {}, error() {} }, vscode: { version: 'synthetic', env: { appHost: 'desktop' }, workspace: { isTrusted: true },
                extensions: { all: [], getExtension: () => visible ? kilo : undefined } } };
        const report = await sandbox.module.exports.checkToolchain(options);
        clearTimeout(timer);
        assert.equal(activations, 1); assert.equal(report.cases.find(c => c.id === 'kilo-discovery').status, 'PASS');
        assert.equal(report.cases.find(c => c.id === 'kilo-activation').status, 'FAIL');
        assert.equal(report.status, 'FAIL'); assert.equal(report.nativeCommands.length, 0); assert.ok(!report.waitingFor);
        assert.ok(report.progress.every((event, index) => event.sequence === index + 1 && Number.isFinite(Date.parse(event.utc))));
        assert.ok(report.progress.some(event => event.id === 'kilo-activation' && event.status === 'FAIL' && event.durationMs >= 0));
        assert.match(JSON.stringify(report), /SYNTHETIC_STOP_BEFORE_NATIVE/); assert.doesNotMatch(JSON.stringify(report), /Kilo Code is not installed/);
        configurationFailure = true;
        const mismatch = await sandbox.module.exports.checkToolchain(options);
        assert.equal(mismatch.status, 'FAIL'); assert.equal(mismatch.productionConfiguration.status, 'FAIL');
        assert.equal(mismatch.productionConfiguration.settingsChanges[0].key, 'editor.fontSize');
        assert.equal(mismatch.cases.find(c => c.id === 'kilo-activation').status, 'BLOCKED'); assert.equal(activations, 1);
        const persisted = JSON.parse(await readFile(mismatch.reportPath, 'utf8'));
        assert.equal(persisted.productionConfiguration.settingsChanges[0].change, 'modified');
        assert.equal(persisted.nativeCommands.length, 0); configurationFailure = false;
        hanging = true;
        const keepAlive = setInterval(() => {}, 100);
        try {
            const timed = await sandbox.module.exports.checkToolchain({ ...options, env: { ...options.env, LOKIENTE_TOOLCHAIN_DEADLINE_UTC: new Date(Date.now() + 200).toISOString() } });
            assert.equal(timed.status, 'BLOCKED'); assert.equal(timed.cases.find(c => c.id === 'kilo-activation').status, 'BLOCKED');
            assert.match(timed.cases.find(c => c.id === 'acceptance-cancelled').evidence, /overall acceptance deadline/);
            assert.equal(timed.nativeCommands.length, 0); assert.equal(JSON.parse(await readFile(timed.reportPath, 'utf8')).status, 'BLOCKED');
            const interrupted = timed.progress.findLast(event => event.status === 'RUNNING');
            assert.ok(interrupted); assert.ok(timed.progress.some(event => event.id === interrupted.id && event.status === 'BLOCKED'));
            const cancelFile = path.join(root, 'diagnostics', 'toolchain', 'a'.repeat(32), 'cancellation.json');
            const cancel = setTimeout(() => { void writeFile(cancelFile, JSON.stringify({ runId: 'a'.repeat(32), reason: 'synthetic native runner stopped' })); }, 50);
            const cancelled = await sandbox.module.exports.checkToolchain(options); clearTimeout(cancel);
            assert.equal(cancelled.status, 'BLOCKED'); assert.match(cancelled.cases.find(c => c.id === 'acceptance-cancelled').evidence, /native runner stopped/);
            await rm(cancelFile); hanging = false;
            await writeFile(path.join(helperSource, 'extension.cjs'), 'synthetic stale helper');
            const stale = await sandbox.module.exports.checkToolchain(options);
            assert.equal(stale.status, 'FAIL'); assert.equal(stale.cases.find(c => c.id === 'managed-helper').status, 'FAIL');
            assert.equal(stale.cases.find(c => c.id === 'kilo-activation').status, 'BLOCKED'); assert.equal(stale.nativeCommands.length, 0);
        } finally { clearInterval(keepAlive); }
    } finally { await rm(root, { recursive: true, force: true }); }
});
