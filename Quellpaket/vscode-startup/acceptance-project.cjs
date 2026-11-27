'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');

// Only the generated acceptance workspace may be initialized. Never adopt a
// user's repository or inherit Git variables which redirect writes elsewhere.
function acceptanceGitEnvironment(env) {
    return Object.fromEntries(Object.entries(env).filter(([name]) => !/^GIT_/i.test(name))
        .concat([['GIT_CONFIG_NOSYSTEM', '1'], ['GIT_CONFIG_GLOBAL', process.platform === 'win32' ? 'NUL' : '/dev/null'], ['GIT_TERMINAL_PROMPT', '0']]));
}

async function prepareAcceptanceProject({ root, runId, git, env = process.env, run }) {
    if (!/^[a-f0-9]{32}$/.test(runId || '') || !path.isAbsolute(root) || !path.isAbsolute(git || '')) throw new Error('Invalid acceptance project or Git executable.');
    const directory = path.join(root, 'diagnostics', 'toolchain', runId), project = path.join(directory, 'project');
    for (const part of ['diagnostics', 'toolchain', runId, 'project'].reduce((paths, part) => [...paths, path.join(paths.at(-1) || root, part)], [])) {
        await fs.mkdir(part).catch(error => { if (error.code !== 'EEXIST') throw error; });
        const stat = await fs.lstat(part);
        if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Acceptance project paths must be ordinary owned directories, without links.');
    }
    const marker = path.join(project, '.lokiente-acceptance.json');
    let owned = false;
    try {
        const stat = await fs.lstat(marker);
        if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('Invalid acceptance ownership marker.');
        const value = JSON.parse(await fs.readFile(marker, 'utf8'));
        if (value.kind !== 'lokiente-generated-acceptance-project' || value.runId !== runId) throw new Error('Acceptance project belongs to another run.');
        owned = true;
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (!owned) {
        if ((await fs.readdir(project)).length) throw new Error('Refusing to initialize a nonempty project without its acceptance ownership marker.');
        await fs.writeFile(marker, JSON.stringify({ kind: 'lokiente-generated-acceptance-project', runId }, null, 2) + '\n', { flag: 'wx' });
        await fs.writeFile(path.join(project, 'README.md'), '# LoKiEnte acceptance workspace\n\nGenerated locally for the toolchain test. Review VS Code Workspace Trust before running it.\nThe test reads generated probe files and requests local LM Studio inference.\n', { flag: 'wx' });
    }
    // A .git file/junction could redirect later writes into another repository.
    const metadata = await fs.lstat(path.join(project, '.git')).catch(error => { if (error.code !== 'ENOENT') throw error; });
    if (metadata && (!metadata.isDirectory() || metadata.isSymbolicLink())) throw new Error('Acceptance Git metadata must be an ordinary local directory.');
    const empty = path.join(directory, 'git-empty');
    await fs.mkdir(empty, { recursive: true });
    if ((await fs.lstat(empty)).isSymbolicLink() || (await fs.readdir(empty)).length) throw new Error('Acceptance Git hooks/template directory must be empty and local.');
    const cleanEnv = acceptanceGitEnvironment(env);
    const prefix = ['-c', `core.hooksPath=${empty}`, '-c', `init.templateDir=${empty}`, '-c', 'commit.gpgSign=false', '-c', 'core.longpaths=true',
        '-c', 'user.name=LoKiEnte Acceptance', '-c', 'user.email=acceptance@users.noreply.github.com'];
    const execute = async args => {
        const result = await run(git, [...prefix, ...args], { cwd: project, env: cleanEnv, timeoutMs: 30000 });
        if (result.code !== 0) throw new Error(`Acceptance Git ${args[0]} failed (exit ${result.code}): ${result.stderr.trim() || result.stdout.trim()}`);
        return result.stdout.trim();
    };
    if (!metadata) {
        await execute(['init', '--initial-branch=main', '.']);
        await execute(['config', '--local', 'core.longpaths', 'true']);
        await execute(['add', '--', 'README.md', '.lokiente-acceptance.json']);
        await execute(['commit', '--no-verify', '-m', 'Initialize generated LoKiEnte acceptance workspace']);
    }
    const topLevel = await execute(['rev-parse', '--show-toplevel']);
    if (path.resolve(topLevel).toLowerCase() !== path.resolve(project).toLowerCase()) throw new Error('Acceptance Git root differs from its generated project.');
    const head = await execute(['rev-parse', '--verify', 'HEAD']);
    if (!/^[a-f0-9]{40,64}$/i.test(head)) throw new Error('Acceptance repository has no verifiable initial commit.');
    return { project, topLevel, head, git, runId, initialized: !metadata };
}

module.exports = { prepareAcceptanceProject, acceptanceGitEnvironment };
if (require.main === module) {
    const [root, runId, git] = process.argv.slice(2);
    const commands = [];
    const run = async (file, args, options) => {
        const started = Date.now(); let result, failure;
        try { result = await require('./toolchain-check.cjs').runNative(file, args, options); return result; }
        catch (error) { failure = error; result = error.nativeResult; throw error; }
        finally { commands.push({ file, args, cwd: options.cwd, timeoutMs: options.timeoutMs, durationMs: Date.now() - started, exitCode: result?.code ?? null,
            stdout: result?.stdout, stderr: result?.stderr, error: failure?.message }); }
    };
    prepareAcceptanceProject({ root, runId, git, run })
        .then(result => process.stdout.write(JSON.stringify({ ...result, nativeCommands: commands }) + '\n'))
        .catch(error => { process.stderr.write(error.message + '\n'); process.exitCode = 1; });
}
