import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import path from 'node:path';
import { test } from 'node:test';
import { createRequire } from 'node:module';
const { createLogger } = createRequire(import.meta.url)('../vscode-startup/diagnostics.cjs');

const source = await readFile(new URL('../vscode-startup/extension.cjs', import.meta.url), 'utf8');
function fixture({ managed = true, open = true, available = true, focus = true, failure = false, foreignProfile = false, scheme = 'file', activation, focusAction, shortDeadline = false } = {}) {
    const calls = [], warnings = [], lines = [], registrations = new Map();
    const dataDirectory = path.resolve('synthetic-managed-profile');
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
        workspace: { getConfiguration(section) { assert.equal(section, 'lokiente.startup'); return { get: () => open }; } },
    };
    const sandbox = { module: { exports: {} }, setTimeout: (fn, ms) => setTimeout(fn, shortDeadline ? 20 : ms), clearTimeout, process: { env: managed ? { LOKIENTE_MANAGED_VSCODE: '1', LOKIENTE_VSCODE_DATA_DIR: dataDirectory } : {} },
        require(id) { if (id === 'node:path') return path; if (id === './kilo-startup.cjs') return { startupSnapshot: async () => {}, async waitForKilo() { const kilo=api.extensions.getExtension('kilocode.kilo-code'); if(!kilo)throw new Error('Kilo is not installed.');return kilo; } }; if (id === './diagnostics.cjs') return { createLogger, startDiagnostics() { return { dispose() {} }; } }; if (id === './security-view.cjs') return { registerSecurityView() {} }; if (id === './sync-guide.cjs') return { registerSyncGuide() {} }; assert.equal(id, 'vscode'); return api; } };
    vm.runInNewContext(source, sandbox);
    return { run: () => sandbox.module.exports.activate(context), context, calls, warnings, lines, registrations };
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
