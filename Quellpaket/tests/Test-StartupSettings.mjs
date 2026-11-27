// Real PowerShell profile generation and files. VS Code APIs and startup
// transforms are explicit synthetic boundaries; no GUI/model inference claim.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { runNative } = require('../vscode-startup/toolchain-check.cjs');
const { verifyAcceptanceConfiguration } = require('../vscode-startup/acceptance-configuration.cjs');
const commands = ['kilo-code.new.agentManagerOpen', 'kilo-code.new.agentManager.showTerminal', 'kilo-code.new.agentManager.previousTerminal', 'kilo-code.new.agentManager.nextTerminal'];
const source = path.resolve(import.meta.dirname, '..');

for (const version of ['1.105.1', '1.148.0']) test(`the actual provisioned ${version} profile survives known VS Code/Kilo startup writes and passes strict parity`, async t => {
    if (process.platform !== 'win32') return t.skip('Native Windows PowerShell provisioning is required.');
    const root = await fs.mkdtemp(path.join(tmpdir(), 'lokiente-startup-settings-'));
    try {
        const script = path.join(root, 'generate.ps1');
        await fs.writeFile(script, 'param($Source,$Root,$CodeVersion)\n$ErrorActionPreference="Stop"\n. (Join-Path $Source "Common.ps1")\n. (Join-Path $Source "VsCodeProfile.ps1")\nUpdate-ShadowVsCodeProfile -InstallRoot $Root -PowerShellPath "synthetic-pwsh.exe" -VsCodeVersion ([version]$CodeVersion)\n');
        const child = await runNative('pwsh.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', script, '-Source', source, '-Root', root, '-CodeVersion', version], { cwd: root, timeoutMs: 60000 });
        assert.equal(child.code, 0, child.stderr);
        const file = path.join(root, 'vscode-data', 'User', 'settings.json'), bytes = await fs.readFile(file), before = JSON.parse(bytes);
        assert.equal(before['extensions.autoUpdate'], version === '1.148.0' ? 'off' : false);
        assert.deepEqual(before['terminal.integrated.commandsToSkipShell'], commands);
        const current = structuredClone(before);
        // Current VS Code normalizes the old boolean; Kilo adds missing commands.
        if (version === '1.148.0' && current['extensions.autoUpdate'] === false) current['extensions.autoUpdate'] = 'off';
        const terminalKey = 'terminal.integrated.commandsToSkipShell';
        current[terminalKey] = [...(current[terminalKey] || []), ...commands.filter(id => !(current[terminalKey] || []).includes(id))];
        if (JSON.stringify(current) !== JSON.stringify(before)) await fs.writeFile(file, JSON.stringify(current));
        assert.deepEqual(await fs.readFile(file), bytes, 'Known upstream initialization must not rewrite the provisioned profile.');

        const runId = 'a'.repeat(32), directory = path.join(root, 'diagnostics', 'toolchain', runId), workspace = path.join(root, 'workspaces', 'test.code-workspace');
        const baseline = { runId, dataDirectory: path.join(root, 'vscode-data'), workspace, userSettings: before, workspaceSettings: {}, files: [] };
        for (const item of [file, workspace, path.join(root, 'kilo-managed', 'kilo.json'), path.join(root, 'toolchain.json'), path.join(root, 'app', 'DesktopRunner.ps1'), path.join(root, 'app', 'Workspace.ps1')]) {
            await fs.mkdir(path.dirname(item), { recursive: true }); if (item !== file) await fs.writeFile(item, '{}');
            baseline.files.push({ path: item, sha256: crypto.createHash('sha256').update(await fs.readFile(item)).digest('hex') });
        }
        await fs.mkdir(directory, { recursive: true }); await fs.writeFile(path.join(directory, 'configuration-baseline.json'), JSON.stringify(baseline));
        const vscode = { workspace: { workspaceFile: { fsPath: workspace }, workspaceFolders: [{ uri: { fsPath: path.join(directory, 'project') } }],
            getConfiguration: () => ({ get: key => current[key], inspect: key => ({ globalValue: current[key] }) }) }, extensions: { all: [] } };
        const options = { root, runId, vscode, env: { LOKIENTE_VSCODE_DATA_DIR: baseline.dataDirectory }, kilo: { extensionPath: path.join(root, 'vscode-extensions', 'kilocode.kilo-code-synthetic') } };
        assert.equal((await verifyAcceptanceConfiguration(options)).status, 'PASS');
        current['extensions.autoUpdate'] = 'on'; current[terminalKey] = ['unexpected.command']; await fs.writeFile(file, JSON.stringify(current));
        const evidence = {};
        await assert.rejects(verifyAcceptanceConfiguration({ ...options, evidence }), /Configuration changed since/);
        assert.deepEqual(evidence.settingsChanges.map(c => c.key), ['extensions.autoUpdate', terminalKey]);
    } finally { assert.ok(path.resolve(root).startsWith(path.resolve(tmpdir()) + path.sep)); await fs.rm(root, { recursive: true, force: true }); }
});
