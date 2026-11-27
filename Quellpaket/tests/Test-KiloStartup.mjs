import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
const { waitForKilo, startupSnapshot } = createRequire(import.meta.url)('../vscode-startup/kilo-startup.cjs');
const logger = { info() {} };
test('installed Kilo discovered after startup is accepted without a false missing-installation error', async () => {
    let visible = false, changed, disposed = false;
    const kilo = { packageJSON: { version: '7.8.32' } };
    const vscode = { extensions: { getExtension: () => visible ? kilo : undefined, onDidChange(fn) { changed = fn; return { dispose() { disposed = true; } }; } } };
    const pending = waitForKilo({ vscode, root: tmpdir(), logger, timeoutMs: 1000 });
    visible = true; changed(); assert.equal(await pending, kilo); assert.equal(disposed, true);
});
test('installed but disabled/unavailable Kilo is diagnosed separately from a missing installation', async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'lokiente-kilo-startup-'));
    try {
        const directory = path.join(root, 'vscode-extensions', 'kilocode.kilo-code-7.8.32'); await mkdir(directory, { recursive: true });
        await writeFile(path.join(directory, 'package.json'), JSON.stringify({ publisher: 'kilocode', name: 'kilo-code', version: '7.8.32', engines: { vscode: '^1.105.1' } }));
        const vscode = { version: 'synthetic', workspace: { isTrusted: false }, extensions: { all: [], getExtension: () => undefined } };
        await assert.rejects(waitForKilo({ vscode, root, logger, timeoutMs: 20, pollMs: 5 }), error => error.code === 'KILO_NOT_DISCOVERED' && !error.message.includes('Run provisioning'));
        const evidence = await startupSnapshot(vscode, root, '0.3.1', 'kilo-failed', Object.assign(new Error('unavailable'), { code: 'KILO_NOT_DISCOVERED' }));
        assert.equal(evidence.installedKilo[0].version, '7.8.32'); assert.equal(evidence.workspaceTrusted, false);
        assert.equal(JSON.parse(await readFile(path.join(root, 'runtime', 'startup-health.json'), 'utf8')).helperVersion, '0.3.1');
    } finally { await rm(root, { recursive: true, force: true }); }
});
test('window disposal cancels discovery and clears the wait', async () => {
    const result = await waitForKilo({ vscode: { extensions: { getExtension() {} } }, root: tmpdir(), logger, isDisposed: () => true, timeoutMs: 500 });
    assert.equal(result, null);
});
