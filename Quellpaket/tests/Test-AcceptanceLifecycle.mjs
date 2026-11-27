import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { EventEmitter } from 'node:events';
import crypto from 'node:crypto';
const { completedAcceptance, announceAcceptance, requestAcceptanceRestart } = createRequire(import.meta.url)('../vscode-startup/acceptance-lifecycle.cjs');
test('finished reports for the same run prevent replay; RUNNING and other run IDs do not', async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'lokiente-acceptance-lifecycle-')), file = path.join(root, 'acceptance.json');
    try {
        assert.equal(await completedAcceptance(file, 'a'), null);
        for (const status of ['PASS', 'FAIL', 'BLOCKED', 'RUNNING']) {
            await writeFile(file, JSON.stringify({ runId: 'a', status }));
            assert.equal(!!await completedAcceptance(file, 'a'), status !== 'RUNNING');
            assert.equal(await completedAcceptance(file, 'b'), null);
        }
        await writeFile(file, '{bad'); await assert.rejects(completedAcceptance(file, 'a'));
    } finally { assert.ok(path.resolve(root).startsWith(path.resolve(tmpdir()) + path.sep)); await rm(root, { recursive: true, force: true }); }
});
test('results use their real verdict, and only an explicit test-window action closes VS Code', async () => {
    for (const status of ['PASS', 'FAIL', 'BLOCKED']) for (const isolated of [false, true]) for (const answer of [undefined, 'Close test window', 'Open report']) {
        const calls = [], messages = [];
        const show = async (...args) => { messages.push(args); return answer; };
        announceAcceptance({ isolated, report: { status, reportPath: 'synthetic.json', cases: [{ status, evidence: 'observed boundary' }] }, logger: { error: (...args) => calls.push(args) },
            vscode: { window: { showInformationMessage: show, showWarningMessage: show, showErrorMessage: show, async showTextDocument(doc) { calls.push(doc); } },
                workspace: { async openTextDocument(file) { return file; } }, commands: { async executeCommand(command) { calls.push(command); } } } });
        await new Promise(resolve => setImmediate(resolve));
        assert.match(messages[0][0], new RegExp(status)); assert.equal(messages[0][1].modal, isolated);
        assert.equal(calls.includes('workbench.action.closeWindow'), isolated && answer === 'Close test window');
        assert.equal(calls.includes('synthetic.json'), answer === 'Open report');
    }
});
test('sidebar acceptance uses the native runner after explicit restart consent without a terminal or stale acceptance environment', async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'lokiente-acceptance-restart-'));
    try {
        await writeFile(path.join(root, 'toolchain.json'), JSON.stringify({ powerShellExecutable: path.join(root, 'synthetic-pwsh.exe') }));
        const directory = path.join(root, 'tooling', 'desktop-runner'); await mkdir(directory, { recursive: true });
        await writeFile(path.join(directory, 'LoKiEnte.exe'), 'synthetic-collector');
        await writeFile(path.join(directory, 'owner.json'), JSON.stringify({ owner: 'lokiente-desktop-runner', binarySha256: crypto.createHash('sha256').update('synthetic-collector').digest('hex') }));
        const calls = [], launches = [];
        const options = { root, logger: { info() {} }, env: { VSCODE_IPC_HOOK: 'stale', ELECTRON_RUN_AS_NODE: '1', LOKIENTE_TOOLCHAIN_RUN_ID: 'stale', LOKIENTE_EDITOR_LAUNCH_ID: 'stale', PATH: 'kept' },
            vscode: { window: { async showInformationMessage() { return 'Close window and run acceptance'; } }, commands: { async executeCommand(command) { calls.push(command); } } },
            launch(file, args, settings) { launches.push({ file, args, settings }); const child = new EventEmitter(); child.unref = () => {}; setImmediate(() => child.emit('spawn')); return child; } };
        await requestAcceptanceRestart(options);
        assert.deepEqual(calls, ['workbench.action.closeWindow']); assert.equal(launches.length, 1);
        assert.equal(launches[0].file, path.join(directory, 'LoKiEnte.exe')); assert.equal(launches[0].args[0], '--editor');
        const request = JSON.parse(await readFile(launches[0].args[1], 'utf8'));
        assert.ok(request.arguments.includes('-WaitForProfileClose')); assert.ok(request.arguments.includes(root)); assert.equal(request.workingDirectory, root);
        assert.equal(launches[0].settings.windowsHide, true); assert.equal(launches[0].settings.shell, false); assert.equal(launches[0].settings.stdio, 'ignore');
        assert.deepEqual(launches[0].settings.env, { PATH: 'kept' });
        options.vscode.window.showInformationMessage = async () => undefined;
        await requestAcceptanceRestart(options); assert.equal(launches.length, 1); assert.equal(calls.length, 1);
    } finally { assert.ok(path.resolve(root).startsWith(path.resolve(tmpdir()) + path.sep)); await rm(root, { recursive: true, force: true }); }
});
