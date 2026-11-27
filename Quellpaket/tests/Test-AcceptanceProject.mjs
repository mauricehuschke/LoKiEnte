// Filesystem/command-boundary regressions; the native Git case is separate.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { prepareAcceptanceProject, acceptanceGitEnvironment } = require('../vscode-startup/acceptance-project.cjs');
const { runNative } = require('../vscode-startup/toolchain-check.cjs');
const id = 'a'.repeat(32), head = 'b'.repeat(40);
const git = process.env.LOKIENTE_TEST_GIT || (process.platform === 'win32' ? path.join(process.env.ProgramFiles, 'Git', 'cmd', 'git.exe') : '/usr/bin/git');
const temporary = async action => {
    const root = await mkdtemp(path.join(tmpdir(), 'lokiente-acceptance-git-'));
    try { return await action(root); } finally {
        assert.ok(path.resolve(root).startsWith(path.resolve(tmpdir()) + path.sep));
        await rm(root, { recursive: true, force: true });
    }
};
function boundary(root, { fail = '' } = {}) {
    const calls = [], project = path.join(root, 'diagnostics', 'toolchain', id, 'project');
    const run = async (file, args, options) => {
        calls.push({ file, args, options });
        const command = args[12];
        if (command === fail) return { code: 1, stdout: '', stderr: 'synthetic Git boundary failure' };
        if (command === 'init') await mkdir(path.join(project, '.git'));
        return { code: 0, stderr: '', stdout: command === 'rev-parse' ? (args.includes('--show-toplevel') ? project : head) : '' };
    };
    return { run, calls, project };
}
test('generated Git preparation uses explicit files, empty hooks/templates and no inherited Git redirections', async () => temporary(async root => {
    const b = boundary(root);
    const env = { PATH: process.env.PATH, GIT_DIR: 'outside', GIT_WORK_TREE: 'outside', GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'core.hooksPath', GIT_CONFIG_VALUE_0: 'outside', GIT_CONFIG_PARAMETERS: 'unsafe', OTHER: 'kept' };
    const result = await prepareAcceptanceProject({ root, runId: id, git, env, run: b.run });
    assert.equal(result.head, head); assert.equal(result.initialized, true);
    assert.deepEqual(b.calls.map(c => c.args[12]), ['init', 'config', 'add', 'commit', 'rev-parse', 'rev-parse']);
    assert.deepEqual(b.calls[2].args.slice(12), ['add', '--', 'README.md', '.lokiente-acceptance.json']);
    for (const call of b.calls) {
        assert.equal(call.options.env.GIT_DIR, undefined); assert.equal(call.options.env.GIT_CONFIG_PARAMETERS, undefined);
        assert.equal(call.options.env.GIT_CONFIG_NOSYSTEM, '1'); assert.equal(call.options.env.OTHER, 'kept');
        assert.ok(call.args.some(arg => arg.startsWith('core.hooksPath='))); assert.ok(call.args.includes('commit.gpgSign=false'));
    }
    const before = b.calls.length; const again = await prepareAcceptanceProject({ root, runId: id, git, run: b.run });
    assert.equal(again.initialized, false); assert.equal(b.calls.length - before, 2);
    assert.equal(JSON.parse(await readFile(path.join(result.project, '.lokiente-acceptance.json'), 'utf8')).runId, id);
}));
test('unowned projects, wrong run markers and redirected .git files remain untouched', async () => temporary(async root => {
    const b = boundary(root); await mkdir(b.project, { recursive: true });
    const user = path.join(b.project, 'user.txt'); await writeFile(user, 'preserve');
    await assert.rejects(prepareAcceptanceProject({ root, runId: id, git, run: b.run }), /nonempty/);
    assert.equal(await readFile(user, 'utf8'), 'preserve'); assert.equal(b.calls.length, 0);
    const marker = path.join(b.project, '.lokiente-acceptance.json');
    await writeFile(marker, JSON.stringify({ kind: 'lokiente-generated-acceptance-project', runId: 'c'.repeat(32) }));
    await assert.rejects(prepareAcceptanceProject({ root, runId: id, git, run: b.run }), /another run/);
    await writeFile(marker, JSON.stringify({ kind: 'lokiente-generated-acceptance-project', runId: id }));
    await writeFile(path.join(b.project, '.git'), 'gitdir: outside');
    await assert.rejects(prepareAcceptanceProject({ root, runId: id, git, run: b.run }), /ordinary local/);
    assert.equal(b.calls.length, 0);
}));
test('a failed first commit or missing HEAD blocks preparation with the actual Git error', async () => temporary(async root => {
    const b = boundary(root, { fail: 'commit' });
    await assert.rejects(prepareAcceptanceProject({ root, runId: id, git, run: b.run }), /commit failed.*synthetic Git boundary failure/);
    await assert.rejects(prepareAcceptanceProject({ root, runId: id, git, run: async () => ({ code: 1, stdout: '', stderr: 'missing HEAD' }) }), /missing HEAD/);
}));
test('Git environment sanitization is case insensitive and preserves unrelated launch variables', () => {
    const env = acceptanceGitEnvironment({ git_dir: 'outside', Git_Index_File: 'outside', KILO_CONFIG: 'managed', PATH: 'kept' });
    assert.equal(env.git_dir, undefined); assert.equal(env.Git_Index_File, undefined); assert.equal(env.KILO_CONFIG, 'managed'); assert.equal(env.PATH, 'kept');
});
test('native Git really creates and verifies a first commit in the generated test project', async t => temporary(async root => {
    try {
        const result = await prepareAcceptanceProject({ root, runId: id, git, run: runNative });
        const log = await runNative(git, ['log', '-1', '--format=%s'], { cwd: result.project, env: acceptanceGitEnvironment(process.env) });
        assert.equal(log.code, 0, log.stderr); assert.match(log.stdout, /Initialize generated LoKiEnte acceptance workspace/);
        assert.match(result.head, /^[a-f0-9]{40,64}$/);
    } catch (error) {
        if (/Cannot start|Win32 error 5|could not create.*pipe|Access is denied|Zugriff verweigert/i.test(error.message)) t.skip(`BLOCKED by development host: ${error.message}`);
        else throw error;
    }
}));
