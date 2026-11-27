import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import path from 'node:path';
import { test } from 'node:test';
import { createRequire } from 'node:module';
const { createLogger } = createRequire(import.meta.url)('../vscode-startup/diagnostics.cjs');

const source = await readFile(new URL('../vscode-startup/extension.cjs', import.meta.url), 'utf8');
function fixture({ managed = true, open = true, available = true, focus = true, failure = false, foreignProfile = false, scheme = 'file', activation, focusAction, shortDeadline = false, acceptance = false, wrongAcceptancePath = false, completed = null, projectOwner } = {}) {
    const calls = [], warnings = [], lines = [], registrations = new Map(), acceptanceRuns = [], results = []; let monitorStops = 0;
    const root = path.resolve('synthetic-install'), runId = 'a'.repeat(32), directory = path.join(root, 'diagnostics', 'toolchain', runId);
    const project = path.join(root, 'diagnostics', 'toolchain', projectOwner || runId, 'project');
    const dataDirectory = acceptance ? path.join(root, 'vscode-data') : path.resolve('synthetic-managed-profile');
    const context = { subscriptions: [], globalStorageUri: { scheme, fsPath: path.join(foreignProfile ? dataDirectory + '-personal' : dataDirectory, 'User', 'globalStorage', 'lokiente.managed-startup') } };
    const api = {
        window: {
            createOutputChannel(name) { assert.equal(name, 'LoKiEnte'); return { info: value => lines.push(value), warn: value => lines.push(value), error: value => lines.push(value), show() {}, dispose() {} }; },
            showWarningMessage: async value => warnings.push(value),
        },
        extensions: { getExtension(id) {
            assert.equal(id, 'kilocode.kilo-code');
            return available ? { async activate() { calls.push('activate'); if (failure) throw new Error('Activation failed'); await activation; } } : undefined;
        } },
        commands: {
            registerCommand(id, callback) { registrations.set(id, callback); return { dispose() {} }; },
            getCommands: async () => focus ? ['kilo-code.SidebarProvider.focus'] : [],
            executeCommand: async id => { calls.push(id); await focusAction; },
        },
        workspace: { workspaceFolders: [{ uri: { fsPath: project } }], getConfiguration(section) { assert.equal(section, 'lokiente.startup'); return { get: () => open }; } },
    };
    const sandbox = { AbortController, module: { exports: {} }, setTimeout: (fn, ms) => setTimeout(fn, shortDeadline ? 20 : ms), clearTimeout, process: { env: managed ? { LOKIENTE_MANAGED_VSCODE: '1', LOKIENTE_VSCODE_DATA_DIR: dataDirectory } : {} },
        require(id) { if (id === 'node:path') return path; if (id === './acceptance-lifecycle.cjs') return { completedAcceptance: async () => completed, requestAcceptanceRestart: async () => results.push({ restart: true }), announceAcceptance: options => results.push(options) }; if (id === './toolchain-check.cjs') return { async checkToolchain(options) { acceptanceRuns.push(options); return { status: 'BLOCKED' }; } }; if (id === './kilo-startup.cjs') return { startupSnapshot: async () => {}, async waitForKilo() { const kilo=api.extensions.getExtension('kilocode.kilo-code'); if(!kilo)throw new Error('Kilo is not installed.');return kilo; } }; if (id === './diagnostics.cjs') return { createLogger, startDiagnostics() { return { snapshot: () => ({}), dispose() { monitorStops++; } }; } }; if (id === './security-view.cjs') return { registerSecurityView() {} }; if (id === './sync-guide.cjs') return { registerSyncGuide() {} }; assert.equal(id, 'vscode'); return api; } };
    if (acceptance) Object.assign(sandbox.process.env, { LOKIENTE_INSTALL_ROOT: root, LOKIENTE_TOOLCHAIN_RUN_ID: runId,
        LOKIENTE_TOOLCHAIN_PROJECT: project, LOKIENTE_TOOLCHAIN_REPORT: path.join(directory, wrongAcceptancePath ? 'other.json' : 'acceptance.json'), ...(projectOwner ? { LOKIENTE_TOOLCHAIN_PROJECT_OWNER: projectOwner } : {}) });
    vm.runInNewContext(source, sandbox);
    return { run: () => sandbox.module.exports.activate(context), context, calls, warnings, lines, registrations, acceptanceRuns, results, get monitorStops() { return monitorStops; } };
}

test('personal windows are untouched even if the helper is installed', async () => {
    const f = fixture({ managed: false }); await f.run();
    assert.deepEqual(f.calls, []); assert.equal(f.context.subscriptions.length, 0); assert.equal(f.registrations.size, 0);
});
test('inherited launcher environment cannot affect a foreign profile', async () => {
    const f = fixture({ foreignProfile: true }); await f.run();
    assert.deepEqual(f.calls, []); assert.equal(f.context.subscriptions.length, 0);
});
test('VS Code userdata storage scheme is supported inside the managed root', async () => {
    const f = fixture({ scheme: 'vscode-userdata' }); await f.run();
    assert.deepEqual(f.calls, ['activate', 'kilo-code.SidebarProvider.focus']);
});
test('unrelated storage schemes are rejected', async () => {
    const f = fixture({ scheme: 'https' }); await f.run(); assert.deepEqual(f.calls, []);
});
test('managed startup activates Kilo before focusing its own view once', async () => {
    const f = fixture(); await f.run();
    assert.deepEqual(f.calls, ['activate', 'kilo-code.SidebarProvider.focus']); assert.equal(f.warnings.length, 0);
    assert.equal(f.registrations.has('lokiente.openKilo'), true);
});
test('startup preference is respected and a manual retry stays available', async () => {
    const f = fixture({ open: false }); await f.run(); assert.deepEqual(f.calls, []);
    await f.registrations.get('lokiente.openKilo')(); assert.deepEqual(f.calls, ['activate', 'kilo-code.SidebarProvider.focus']);
});

test('installed helper starts acceptance in its ordinary production-profile window without a development host', async () => {
    const f = fixture({ acceptance: true }); await f.run();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(f.acceptanceRuns.length, 1); assert.deepEqual(f.calls, []);
    assert.equal(f.acceptanceRuns[0].runId, 'a'.repeat(32));
    assert.equal(path.basename(f.acceptanceRuns[0].reportPath), 'acceptance.json');
    assert.ok(f.monitorStops >= 1); assert.equal(f.results[0].report.status, 'BLOCKED'); assert.equal(f.results[0].isolated, true);
});

test('acceptance environment cannot start a test for another report or workspace', async () => {
    const f = fixture({ acceptance: true, wrongAcceptancePath: true }); await f.run();
    assert.equal(f.acceptanceRuns.length, 0); assert.deepEqual(f.calls, []);
    assert.ok(f.lines.some(line => line.includes('Acceptance launch does not match')));
});
for (const [name, options] of [['missing Kilo', { available: false }], ['changed Kilo command', { focus: false }], ['activation error', { failure: true }]]) {
    test(`${name} produces a visible warning without opening the built-in chat`, async () => {
        const f = fixture(options); await f.run();
        assert.equal(f.warnings.length, 1); assert.ok(f.lines.some(line => line.includes('Could not open Kilo:')));
        assert.ok(!f.calls.includes('kilo-code.SidebarProvider.focus'));
    });
}
test('window disposal while Kilo activates cancels the focus action', async () => {
    let release; const activation = new Promise(resolve => { release = resolve; });
    const f = fixture({ activation }); const pending = f.run();
    while (!f.calls.includes('activate')) await new Promise(resolve => setImmediate(resolve));
    for (const disposable of f.context.subscriptions) disposable.dispose();
    release(); await pending; assert.deepEqual(f.calls, ['activate']); assert.equal(f.warnings.length, 0);
});

test('a hanging Kilo sidebar reports a visible timeout instead of leaving startup pending', async () => {
    const keepAlive = setInterval(() => {}, 50);
    try {
        const f = fixture({ shortDeadline: true, focusAction: new Promise(() => {}) }); await f.run();
        assert.equal(f.warnings.length, 1); assert.ok(f.lines.some(line => line.includes('sidebar focus timed out')));
        assert.ok(!f.lines.some(line => line.includes('sidebar focus command completed')));
    } finally { clearInterval(keepAlive); }
});

test('Extension Host reload does not replay a completed acceptance and stops background forwarding', async () => {
    const f = fixture({ acceptance: true, completed: { runId: 'a'.repeat(32), status: 'BLOCKED' } }); await f.run();
    assert.equal(f.acceptanceRuns.length, 0); assert.equal(f.monitorStops, 1); assert.equal(f.results[0].report.status, 'BLOCKED');
});
test('normal desktop diagnostics stay active after startup', async () => {
    const f = fixture(); await f.run(); assert.equal(f.monitorStops, 0);
});

test('sidebar command restarts through native acceptance instead of testing a different profile in place', async () => {
    const f=fixture(); await f.run(); await f.registrations.get('lokiente.toolchain.check')(); assert.equal(f.results[0].restart, true); assert.equal(f.acceptanceRuns.length, 0);
});
test('a new acceptance can use the previous generated project without changing the work profile or reusing the report ID', async () => {
    const f = fixture({ acceptance: true, projectOwner: 'b'.repeat(32) }); await f.run(); await new Promise(resolve => setImmediate(resolve));
    assert.equal(f.acceptanceRuns.length, 1); assert.equal(f.acceptanceRuns[0].runId, 'a'.repeat(32));
    assert.equal(path.basename(path.dirname(f.acceptanceRuns[0].project)), 'b'.repeat(32));
    const invalid = fixture({ acceptance: true, projectOwner: '../outside' }); await invalid.run(); assert.equal(invalid.acceptanceRuns.length, 0);
});
