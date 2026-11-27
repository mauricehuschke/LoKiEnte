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
const digest = value => crypto.createHash('sha256').update(value).digest('hex');

// VS Code settings are JSON with comments and trailing commas. Preserve strings
// verbatim (including URL/comment-like text); let JSON.parse reject other syntax.
function parseSettings(text) {
    const characters = [...text.replace(/^\uFEFF/, '')];
    let quoted = false;
    for (let i = 0; i < characters.length; i++) {
        if (quoted) { if (characters[i] === '\\') i++; else if (characters[i] === '"') quoted = false; continue; }
        if (characters[i] === '"') { quoted = true; continue; }
        if (characters[i] !== '/') continue;
        const next = characters[i + 1];
        if (next !== '/' && next !== '*') continue;
        const start = i;
        if (next === '/') { while (i < characters.length && !['\r', '\n'].includes(characters[i])) i++; }
        else {
            i += 2;
            while (i < characters.length && !(characters[i] === '*' && characters[i + 1] === '/')) i++;
            if (i >= characters.length) throw new SyntaxError('Unterminated settings comment.');
            i += 2;
        }
        for (let n = start; n < i; n++) if (!['\r', '\n'].includes(characters[n])) characters[n] = ' ';
        i--;
    }
    quoted = false;
    for (let i = 0; i < characters.length; i++) {
        if (quoted) { if (characters[i] === '\\') i++; else if (characters[i] === '"') quoted = false; continue; }
        if (characters[i] === '"') quoted = true;
        else if (characters[i] === ',') {
            let next = i + 1;
            while (/\s/.test(characters[next] || '') && next < characters.length) next++;
            if (['}', ']'].includes(characters[next])) {
                let previous = i - 1;
                while (previous >= 0 && /\s/.test(characters[previous])) previous--;
                if (previous < 0 || ['[', '{', ':', ','].includes(characters[previous])) throw new SyntaxError('Invalid trailing settings comma.');
                characters[i] = ' ';
            }
        }
    }
    const value = JSON.parse(characters.join(''));
    if (!object(value)) throw new Error('VS Code settings must be a JSON object.');
    return value;
}

async function verifyAcceptanceConfiguration({ vscode, root, runId, env, kilo, evidence = {} }) {
    const ownerRunId = env.LOKIENTE_TOOLCHAIN_PROJECT_OWNER || runId;
    if (!/^[a-f0-9]{32}$/.test(ownerRunId)) throw new Error('Invalid generated project owner.');
    const file = path.join(root, 'diagnostics', 'toolchain', runId, 'configuration-baseline.json');
    Object.assign(evidence, { mode: 'same-production-profile', baselinePath: file, files: [], settingsChanges: [], effectiveMismatches: [] });
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
        !equalPath(vscode.workspace.workspaceFolders?.[0]?.uri?.fsPath, path.join(root, 'diagnostics', 'toolchain', ownerRunId, 'project'))) throw new Error('Acceptance does not use the production managed profile, extension directory and generated production workspace.');
    const files = evidence.files, failures = [];
    for (const item of baseline.files) {
        const bytes = await fs.readFile(item.path), hash = digest(bytes);
        const entry = { path: item.path, sha256: hash, expectedSha256: item.sha256, byteMatch: hash === item.sha256, comparison: 'exact-bytes' };
        files.push(entry);
        if (equalPath(item.path, path.join(root, 'vscode-data', 'User', 'settings.json'))) {
            entry.comparison = 'jsonc-setting-values';
            let current;
            try { current = parseSettings(bytes.toString('utf8')); }
            catch (error) { entry.error = 'Settings JSONC could not be parsed.'; throw new Error(`Invalid VS Code settings JSONC: ${item.path}`); }
            const keys = [...new Set([...Object.keys(baseline.userSettings), ...Object.keys(current)])].sort();
            evidence.settingsChanges = keys.filter(key => !Object.hasOwn(current, key) || !Object.hasOwn(baseline.userSettings, key) || stable(current[key]) !== stable(baseline.userSettings[key]))
                .map(key => ({ key, change: !Object.hasOwn(current, key) ? 'removed' : !Object.hasOwn(baseline.userSettings, key) ? 'added' : 'modified' }));
            entry.expectedSemanticSha256 = digest(stable(baseline.userSettings)); entry.semanticSha256 = digest(stable(current));
            entry.semanticMatch = evidence.settingsChanges.length === 0;
            if (!entry.semanticMatch) failures.push(`${item.path} (settings: ${evidence.settingsChanges.map(change => change.key).join(', ')})`);
        } else if (!entry.byteMatch) failures.push(item.path);
    }
    if (failures.length) throw new Error(`Configuration changed since the production launch baseline: ${failures.join('; ')}`);
    const resource = vscode.workspace.workspaceFolders[0].uri;
    const settings = vscode.workspace.getConfiguration(undefined, resource);
    const expected = merge(baseline.userSettings, baseline.workspaceSettings);
    const mismatches = Object.keys(expected).filter(key => {
        const scope = settings.inspect?.(key);
        if (scope && (Object.hasOwn(baseline.userSettings, key) && stable(scope.globalValue) !== stable(baseline.userSettings[key]) ||
            Object.hasOwn(baseline.workspaceSettings, key) && stable(scope.workspaceValue) !== stable(baseline.workspaceSettings[key]))) return true;
        return !contains(settings.get(key), expected[key]);
    });
    evidence.effectiveMismatches = mismatches;
    if (mismatches.length) throw new Error(`Effective VS Code settings differ from the real managed profile/workspace: ${mismatches.join(', ')}`);
    const savedKilo = JSON.parse(await fs.readFile(path.join(root, 'kilo-managed', 'kilo.json'), 'utf8'));
    if (stable(savedKilo) !== stable(JSON.parse(env.KILO_CONFIG_CONTENT || '{}'))) throw new Error('The running Kilo configuration differs from the saved production configuration.');
    const visibleExtensions = vscode.extensions.all.map(extension => ({ id: extension.id, version: extension.packageJSON.version, active: extension.isActive }));
    return Object.assign(evidence, { status: 'PASS', dataDirectory: baseline.dataDirectory, extensionsDirectory: path.join(root, 'vscode-extensions'), workspace: baseline.workspace,
        settingsCompared: Object.keys(expected).sort(), comparison: 'Settings JSONC values, explicit effective values and exposed user/workspace scopes; inherited default object keys are preserved. All other baseline files require exact bytes.', visibleExtensions,
        launchPolicy: 'Desktop runner, arguments, environment and workspace generator are shared with Start-LocalAI.ps1. Only the generated project and acceptance run/report controls differ.' });
}

module.exports = { verifyAcceptanceConfiguration, parseSettings };
