'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const equalPath = (a, b) => typeof a === 'string' && typeof b === 'string' && path.resolve(a).toLowerCase() === path.resolve(b).toLowerCase();
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const canonical = value => Array.isArray(value) ? value.map(canonical) : object(value) ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
const stable = value => JSON.stringify(canonical(value));
const merge = (base, extra) => object(base) && object(extra) ? Object.fromEntries([...new Set([...Object.keys(base), ...Object.keys(extra)])].map(key => [key,
    Object.hasOwn(extra, key) ? merge(base[key], extra[key]) : base[key]])) : extra;
// VS Code merges default object keys into configured objects. Compare every
// explicit value, retaining inherited default keys; arrays are replaced in full.
const contains = (actual, expected) => object(expected) ? object(actual) && Object.keys(expected).every(key => contains(actual[key], expected[key])) : stable(actual) === stable(expected);

async function verifyAcceptanceConfiguration({ vscode, root, runId, env, kilo }) {
    const file = path.join(root, 'diagnostics', 'toolchain', runId, 'configuration-baseline.json');
    const baseline = JSON.parse(await fs.readFile(file, 'utf8'));
    if (!object(baseline.userSettings) || !object(baseline.workspaceSettings) || !Array.isArray(baseline.files)) throw new Error('Invalid production configuration baseline.');
    const relativeWorkspace = typeof baseline.workspace === 'string' ? path.relative(path.join(root, 'workspaces'), baseline.workspace) : '..';
    const expectedFiles = [path.join(root, 'vscode-data', 'User', 'settings.json'), baseline.workspace, path.join(root, 'kilo-managed', 'kilo.json'),
        path.join(root, 'toolchain.json'), path.join(root, 'app', 'DesktopRunner.ps1'), path.join(root, 'app', 'Workspace.ps1')];
    const normalized = files => files.map(value => path.resolve(value).toLowerCase()).sort();
    if (relativeWorkspace === '..' || relativeWorkspace.startsWith(`..${path.sep}`) || path.isAbsolute(relativeWorkspace) ||
        stable(normalized(baseline.files.map(value => value.path))) !== stable(normalized(expectedFiles))) throw new Error('Production configuration baseline does not cover the managed workspace and required files.');
    if (baseline.runId !== runId || !equalPath(env.LOKIENTE_VSCODE_DATA_DIR, path.join(root, 'vscode-data')) ||
        !equalPath(baseline.dataDirectory, env.LOKIENTE_VSCODE_DATA_DIR) || !equalPath(vscode.workspace.workspaceFile?.fsPath, baseline.workspace) ||
        !equalPath(path.dirname(kilo.extensionPath), path.join(root, 'vscode-extensions')) ||
        !equalPath(vscode.workspace.workspaceFolders?.[0]?.uri?.fsPath, path.join(root, 'diagnostics', 'toolchain', runId, 'project'))) throw new Error('Acceptance does not use the production managed profile, extension directory and generated production workspace.');
    const files = [];
    for (const item of baseline.files) {
        const hash = crypto.createHash('sha256').update(await fs.readFile(item.path)).digest('hex');
        if (hash !== item.sha256) throw new Error(`Configuration changed since the production launch baseline: ${item.path}`);
        files.push({ path: item.path, sha256: hash });
    }
    const resource = vscode.workspace.workspaceFolders[0].uri;
    const settings = vscode.workspace.getConfiguration(undefined, resource);
    const expected = merge(baseline.userSettings, baseline.workspaceSettings);
    const mismatches = Object.keys(expected).filter(key => {
        const scope = settings.inspect?.(key);
        if (scope && (Object.hasOwn(baseline.userSettings, key) && stable(scope.globalValue) !== stable(baseline.userSettings[key]) ||
            Object.hasOwn(baseline.workspaceSettings, key) && stable(scope.workspaceValue) !== stable(baseline.workspaceSettings[key]))) return true;
        return !contains(settings.get(key), expected[key]);
    });
    if (mismatches.length) throw new Error(`Effective VS Code settings differ from the real managed profile/workspace: ${mismatches.join(', ')}`);
    const savedKilo = JSON.parse(await fs.readFile(path.join(root, 'kilo-managed', 'kilo.json'), 'utf8'));
    if (stable(savedKilo) !== stable(JSON.parse(env.KILO_CONFIG_CONTENT || '{}'))) throw new Error('The running Kilo configuration differs from the saved production configuration.');
    const visibleExtensions = vscode.extensions.all.map(extension => ({ id: extension.id, version: extension.packageJSON.version, active: extension.isActive }));
    return { mode: 'same-production-profile', dataDirectory: baseline.dataDirectory, extensionsDirectory: path.join(root, 'vscode-extensions'), workspace: baseline.workspace,
        settingsCompared: Object.keys(expected).sort(), comparison: 'Explicit effective values and exposed user/workspace scopes; inherited default object keys are preserved.', files, visibleExtensions,
        launchPolicy: 'Desktop runner, arguments, environment and workspace generator are shared with Start-LocalAI.ps1. Only the generated project and acceptance run/report controls differ.' };
}

module.exports = { verifyAcceptanceConfiguration };
