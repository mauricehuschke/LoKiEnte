// Native Windows lock regression + deterministic I/O failure boundaries.
// No VS Code/model inference is claimed by these tests.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import * as fs from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
const { atomic, checkToolchain } = createRequire(import.meta.url)('../vscode-startup/toolchain-check.cjs');
const temporary = async action => {
    const root = await fs.mkdtemp(path.join(tmpdir(), 'lokiente-persistence-'));
    try { return await action(root); }
    finally { assert.ok(path.resolve(root).startsWith(path.resolve(tmpdir()) + path.sep)); await fs.rm(root, { recursive: true, force: true }); }
};
const ioError = code => Object.assign(new Error(`Synthetic ${code} at rename`), { code, syscall: 'rename' });

test('transient Windows replacement codes retry without deleting the previous JSON snapshot', async () => temporary(async root => {
    for (const code of ['EPERM', 'EACCES', 'EBUSY']) {
        const file = path.join(root, `${code}.json`); await fs.writeFile(file, '{"value":"old"}');
        let calls = 0;
        const io = { ...fs, async rename(from, to) {
            assert.deepEqual(JSON.parse(await fs.readFile(to, 'utf8')), { value: 'old' });
            if (++calls < 3) throw ioError(code);
            await fs.rename(from, to);
        } };
        assert.equal((await atomic(file, '{"value":"new"}', { io, timeoutMs: 1000, retryDelayMs: 1 })).retries, 2);
        assert.deepEqual(JSON.parse(await fs.readFile(file, 'utf8')), { value: 'new' });
    }
    assert.equal((await fs.readdir(root)).filter(name => name.endsWith('.tmp')).length, 0);
}));

test('permanent replacement failure preserves the old report and the complete pending snapshot', async () => temporary(async root => {
    const file = path.join(root, 'acceptance.json'); await fs.writeFile(file, '{"status":"RUNNING"}');
    let error, calls = 0;
    try { await atomic(file, '{"status":"FAIL"}', { timeoutMs: 20, retryDelayMs: 1, io: { ...fs, async rename() { calls++; throw ioError('EPERM'); } } }); }
    catch (e) { error = e; }
    assert.equal(error.code, 'EPERM'); assert.ok(calls > 1); assert.match(error.message, /Pending snapshot/);
    assert.equal(JSON.parse(await fs.readFile(file, 'utf8')).status, 'RUNNING');
    assert.equal(JSON.parse(await fs.readFile(error.temporaryFile, 'utf8')).status, 'FAIL');
}));

test('unrelated rename errors fail immediately instead of being hidden by permission retries', async () => temporary(async root => {
    let calls = 0;
    await assert.rejects(atomic(path.join(root, 'report.json'), '{}', { io: { ...fs, async rename() { calls++; throw ioError('ENOSPC'); } } }), error => error.code === 'ENOSPC');
    assert.equal(calls, 1);
}));

test('a real Windows reader without Delete sharing reproduces EPERM and replacement recovers after release', async t => {
    if (process.platform !== 'win32') return t.skip('Windows FileShare semantics require native Windows.');
    await temporary(async root => {
        const file = path.join(root, 'acceptance.json'), script = path.join(root, 'reader.ps1');
        await fs.writeFile(file, '{"status":"RUNNING"}');
        await fs.writeFile(script, 'param($Path)\n$s=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)\ntry{[Console]::WriteLine("READY");[Console]::Out.Flush();[void][Console]::In.ReadLine()}finally{$s.Dispose()}\n');
        const child = spawn('pwsh.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', script, '-Path', file], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        child.stdin.on('error', () => {});
        const closed = once(child, 'close');
        const deadline = setTimeout(() => child.kill(), 15000);
        try {
            await new Promise((resolve, reject) => {
                let text = '';
                child.stdout.on('data', data => { text += data; if (text.includes('READY')) resolve(); });
                child.once('error', reject); child.once('exit', code => reject(new Error(`Lock holder exited: ${code}`)));
            });
            const before = path.join(root, 'raw.tmp'); await fs.writeFile(before, '{}');
            await assert.rejects(fs.rename(before, file), error => ['EPERM', 'EACCES', 'EBUSY'].includes(error.code));
            await fs.unlink(before);
            const release = setTimeout(() => child.stdin.end('release\n'), 250);
            try {
                const result = await atomic(file, '{"status":"PASS"}');
                assert.ok(result.retries > 0); assert.equal(JSON.parse(await fs.readFile(file, 'utf8')).status, 'PASS');
            } finally { clearTimeout(release); }
        } finally {
            child.stdin.end('release\n'); await closed; clearTimeout(deadline);
        }
    });
});

test('a permanently locked main report yields a separate terminal FAIL report and no native/model execution', async () => temporary(async root => {
    const runId = 'a'.repeat(32), directory = path.join(root, 'diagnostics', 'toolchain', runId), reportPath = path.join(directory, 'acceptance.json');
    await fs.mkdir(directory, { recursive: true }); await fs.writeFile(reportPath, JSON.stringify({ runId, status: 'RUNNING' }));
    const io = { ...fs, async rename(from, to) { if (to === reportPath) throw ioError('EPERM'); return await fs.rename(from, to); } };
    const report = await checkToolchain({ root, runId, reportPath, env: {}, logger: { info() {}, warn() {}, error() {} },
        persistenceOptions: { io, timeoutMs: 0 }, vscode: { version: 'synthetic', env: { appHost: 'web' } } });
    assert.equal(report.status, 'FAIL'); assert.equal(report.nativeCommands.length, 0);
    assert.match(report.reportPath, /acceptance\.failure\.json$/); assert.equal(report.persistenceFailure.code, 'EPERM');
    assert.equal(JSON.parse(await fs.readFile(reportPath, 'utf8')).status, 'RUNNING');
    assert.equal(JSON.parse(await fs.readFile(report.reportPath, 'utf8')).status, 'FAIL');
    assert.match(await fs.readFile(report.reportPath.replace('.json', '.junit.xml'), 'utf8'), /report-persistence/);
    assert.ok(report.required.every(id => report.cases.some(entry => entry.id === id && entry.status !== 'PASS')));
}));

test('the actual PowerShell reader and report writer exchange only complete JSON under concurrent replacement', async t => {
    if (process.platform !== 'win32') return t.skip('Windows FileShare semantics require native Windows.');
    await temporary(async root => {
        const file = path.join(root, 'acceptance.json'), script = path.join(root, 'reader.ps1');
        const helper = path.resolve(import.meta.dirname, '../ToolchainAcceptance.ps1');
        const padding = 'x'.repeat(512 * 1024);
        await fs.writeFile(file, JSON.stringify({ revision: 0, padding }));
        await fs.writeFile(script, 'param($Helper,$Path)\n$ErrorActionPreference="Stop"\n. $Helper\n[Console]::WriteLine("READY");[Console]::Out.Flush();[void][Console]::In.ReadLine()\n1..150|ForEach-Object{$r=Read-ShadowAcceptanceJson -Path $Path;if($r.revision -lt 0 -or $r.padding.Length -ne 524288){throw "Incomplete snapshot"}}\n[Console]::WriteLine("COMPLETE")\n');
        const child = spawn('pwsh.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', script, '-Helper', helper, '-Path', file], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
        const closed = once(child, 'close'); let stdout = '', stderr = '';
        child.stdout.on('data', data => { stdout += data; }); child.stderr.on('data', data => { stderr += data; });
        child.stdin.on('error', () => {});
        const deadline = setTimeout(() => child.kill(), 20000);
        try {
            await new Promise((resolve, reject) => {
                child.stdout.on('data', () => { if (stdout.includes('READY')) resolve(); });
                child.once('error', reject); child.once('exit', code => reject(new Error(`Reader exited: ${code}. ${stderr}`)));
            });
            child.stdin.end('start\n');
            for (let revision = 1; revision <= 150; revision++) {
                await atomic(file, JSON.stringify({ revision, padding }));
            }
            const [code] = await closed;
            assert.equal(code, 0, stderr); assert.match(stdout, /COMPLETE/);
        } finally { child.kill(); await closed; clearTimeout(deadline); }
    });
});
