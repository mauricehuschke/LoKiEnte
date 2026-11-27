import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
const { verifyAcceptanceConfiguration, parseSettings } = createRequire(import.meta.url)('../vscode-startup/acceptance-configuration.cjs');
const id = 'a'.repeat(32);
const fixture = async action => {
    const root = await mkdtemp(path.join(tmpdir(), 'lokiente-config-parity-'));
    try {
        const directory = path.join(root, 'diagnostics', 'toolchain', id); await mkdir(directory, { recursive: true });
        await mkdir(path.join(root, 'kilo-managed')); await writeFile(path.join(root, 'kilo-managed', 'kilo.json'), '{}');
        await mkdir(path.join(root, 'workspaces'));
        const workspace = path.join(root, 'workspaces', 'test.code-workspace'); await writeFile(workspace, '{}');
        const settings = { 'telemetry.telemetryLevel': 'off', 'editor.fontSize': 16, 'terminal.integrated.profiles.windows': { 'LoKiEnte PowerShell': { path: 'synthetic-pwsh', args: ['-NoLogo'] } } };
        const baseline = { runId: id, dataDirectory: path.join(root, 'vscode-data'), workspace, userSettings: settings, workspaceSettings: { 'chat.disableAIFeatures': true },
            files: [] };
        for (const file of [path.join(root, 'vscode-data', 'User', 'settings.json'), workspace, path.join(root, 'kilo-managed', 'kilo.json'), path.join(root, 'toolchain.json'),
            path.join(root, 'app', 'DesktopRunner.ps1'), path.join(root, 'app', 'Workspace.ps1')]) {
            const contents = file.endsWith('settings.json') ? JSON.stringify(settings) : '{}';
            await mkdir(path.dirname(file), { recursive: true }); await writeFile(file, contents);
            baseline.files.push({ path: file, sha256: crypto.createHash('sha256').update(contents).digest('hex') });
        }
        await writeFile(path.join(directory, 'configuration-baseline.json'), JSON.stringify(baseline));
        const actual = structuredClone({ ...settings, ...baseline.workspaceSettings });
        const vscode = { workspace: { workspaceFile: { fsPath: workspace }, workspaceFolders: [{ uri: { fsPath: path.join(directory, 'project') } }], getConfiguration: () => ({ get: key => actual[key] }) },
            extensions: { all: [{ id: 'kilocode.kilo-code', packageJSON: { version: 'synthetic' }, isActive: false }] } };
        await action({ root, runId: id, vscode, env: { LOKIENTE_VSCODE_DATA_DIR: baseline.dataDirectory }, kilo: { extensionPath: path.join(root, 'vscode-extensions', 'kilocode.kilo-code-synthetic') } }, actual, workspace);
    } finally { assert.ok(path.resolve(root).startsWith(path.resolve(tmpdir()) + path.sep)); await rm(root, { recursive: true, force: true }); }
};
test('production parity compares custom and managed effective settings, hashes and actual extension paths', async () => fixture(async options => {
    const evidence = await verifyAcceptanceConfiguration(options);
    assert.equal(evidence.mode, 'same-production-profile'); assert.equal(evidence.settingsCompared.length, 4);
    assert.equal(evidence.visibleExtensions[0].id, 'kilocode.kilo-code');
}));

test('settings formatting, BOM, comments, trailing commas and key order preserve production parity with original hashes retained', async () => fixture(async options => {
    const file = path.join(options.root, 'vscode-data', 'User', 'settings.json');
    const original = JSON.parse(await readFile(file, 'utf8'));
    const reordered = Object.fromEntries(Object.entries(original).reverse());
    await writeFile(file, '\uFEFF// Settings rewritten by an editor\r\n' + JSON.stringify(reordered, null, 4).replace(/\n}$/, ',\n}'));
    const result = await verifyAcceptanceConfiguration(options), entry = result.files.find(item => item.path === file);
    assert.equal(result.status, 'PASS'); assert.equal(entry.byteMatch, false); assert.equal(entry.semanticMatch, true);
    assert.notEqual(entry.sha256, entry.expectedSha256); assert.equal(entry.semanticSha256, entry.expectedSemanticSha256);
    assert.deepEqual(result.settingsChanges, []);
}));

test('added, removed and modified settings remain failures and expose key names without values', async () => fixture(async options => {
    const file = path.join(options.root, 'vscode-data', 'User', 'settings.json');
    const original = JSON.parse(await readFile(file, 'utf8'));
    for (const [changed, key, change] of [
        [{ ...original, 'security.workspace.trust.enabled': false }, 'security.workspace.trust.enabled', 'added'],
        [Object.fromEntries(Object.entries(original).filter(([key]) => key !== 'editor.fontSize')), 'editor.fontSize', 'removed'],
        [{ ...original, 'editor.fontSize': 14 }, 'editor.fontSize', 'modified'],
    ]) {
        const evidence = {}; await writeFile(file, JSON.stringify(changed));
        await assert.rejects(verifyAcceptanceConfiguration({ ...options, evidence }), /Configuration changed since/);
        assert.deepEqual(evidence.settingsChanges, [{ key, change }]); assert.equal(evidence.files[0].semanticMatch, false);
        assert.equal(evidence.files.length, 6);
    }
}));

test('JSONC parsing preserves quoted URLs, escaped quotes and comment-like text and rejects malformed settings', () => {
    const original = { url: 'https://example.invalid/a//b/*literal*/', quote: '"quoted\\path,}', nested: { array: [1, 2] } };
    assert.deepEqual(parseSettings('/* header */\n' + JSON.stringify(original).replace('[1,2]', '[1,2,/* end */]')), original);
    assert.deepEqual(parseSettings('// CR-only newline\r{"x":1,}'), { x: 1 });
    for (const value of ['{"x":1 /* unfinished', '{"x":,}', '{,}', '{"x":[,]}', '[]', 'null', '{"x":1} garbage']) assert.throws(() => parseSettings(value));
});

test('malformed settings and semantic differences in saved source files cannot be accepted as formatting changes', async () => fixture(async (options, actual, workspace) => {
    const file = path.join(options.root, 'vscode-data', 'User', 'settings.json'), original = await readFile(file);
    await writeFile(file, '{"broken":');
    await assert.rejects(verifyAcceptanceConfiguration(options), /Invalid VS Code settings JSONC/);
    await writeFile(file, original); await writeFile(workspace, '{ }');
    await assert.rejects(verifyAcceptanceConfiguration(options), /Configuration changed since/);
}));
test('isolated/default profiles, different extension paths and different workspace files cannot pass parity', async () => fixture(async options => {
    for (const changed of [
        { env: { LOKIENTE_VSCODE_DATA_DIR: path.join(options.root, 'other-profile') } },
        { kilo: { extensionPath: path.join(options.root, 'other-extensions', 'kilo') } },
        { vscode: { ...options.vscode, workspace: { ...options.vscode.workspace, workspaceFile: { fsPath: 'other.code-workspace' } } } },
    ]) await assert.rejects(verifyAcceptanceConfiguration({ ...options, ...changed }), /production managed profile/);
}));
test('workspace overrides and changed source bytes block parity instead of reporting PASS', async () => fixture(async (options, actual, workspace) => {
    actual['editor.fontSize'] = 14;
    await assert.rejects(verifyAcceptanceConfiguration(options), /editor.fontSize/);
    actual['editor.fontSize'] = 16; await writeFile(workspace, '{"changed":true}');
    await assert.rejects(verifyAcceptanceConfiguration(options), /changed since/);
}));
test('inherited object defaults are allowed while configured nested values, scopes and Kilo config must match', async () => fixture(async (options, actual) => {
    actual['terminal.integrated.profiles.windows'].PowerShell = { source: 'PowerShell', icon: 'terminal-powershell' };
    await verifyAcceptanceConfiguration(options);
    actual['terminal.integrated.profiles.windows']['LoKiEnte PowerShell'].path = 'wrong-pwsh';
    await assert.rejects(verifyAcceptanceConfiguration(options), /terminal.integrated.profiles.windows/);
    actual['terminal.integrated.profiles.windows']['LoKiEnte PowerShell'].path = 'synthetic-pwsh';
    options.vscode.workspace.getConfiguration = () => ({ get: key => actual[key], inspect: key => ({ globalValue: key === 'editor.fontSize' ? 14 : actual[key] }) });
    await assert.rejects(verifyAcceptanceConfiguration(options), /editor.fontSize/);
    options.vscode.workspace.getConfiguration = () => ({ get: key => actual[key] });
    options.env.KILO_CONFIG_CONTENT = '{"changed":true}';
    await assert.rejects(verifyAcceptanceConfiguration(options), /Kilo configuration differs/);
}));
test('configuration parity accepts the same owned/trusted project with a fresh report ID and rejects path redirection', async () => fixture(async options => {
    const runId = 'b'.repeat(32), directory = path.join(options.root, 'diagnostics', 'toolchain', runId); await mkdir(directory);
    const baseline = JSON.parse(await readFile(path.join(options.root, 'diagnostics', 'toolchain', id, 'configuration-baseline.json'), 'utf8'));
    baseline.runId = runId; await writeFile(path.join(directory, 'configuration-baseline.json'), JSON.stringify(baseline));
    const reused = { ...options, runId, env: { ...options.env, LOKIENTE_TOOLCHAIN_PROJECT_OWNER: id } };
    assert.equal((await verifyAcceptanceConfiguration(reused)).mode, 'same-production-profile');
    await assert.rejects(verifyAcceptanceConfiguration({ ...reused, env: { ...reused.env, LOKIENTE_TOOLCHAIN_PROJECT_OWNER: '../other' } }), /Invalid generated project owner/);
    await assert.rejects(verifyAcceptanceConfiguration({ ...reused, env: { ...reused.env, LOKIENTE_TOOLCHAIN_PROJECT_OWNER: runId } }), /production managed profile/);
}));
