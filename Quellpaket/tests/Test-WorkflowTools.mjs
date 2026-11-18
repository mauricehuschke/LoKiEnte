// Integration tests use an isolated fake PowerShell runner. No models,
// provisioning, user project or network access is involved.
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { createWorkflowTools, inside, managedPath, stateView, TERMINAL_STATES } from '../KiloWorkflowTools.mjs';
import { runJob } from '../WorkflowJob.mjs';

const source = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const temporaryBase = path.resolve(process.env.LOKI_TEST_TEMP || os.tmpdir());
const fixture = await fs.mkdtemp(path.join(temporaryBase, 'loki-workflow-tools-'));
const root = path.join(fixture, 'install with spaces');
const project = path.join(fixture, 'project with spaces');
const secondProject = path.join(fixture, 'second project');
const calls = [];
const context = { directory: project, sessionID: 'fixture-session', abort: new AbortController().signal, ask: async input => { calls.push(input.permission); } };
let passed = 0;
const started = [];
let tools;
function runIdFrom(text) { const match = text.match(/Auftrag: `([a-f0-9-]{36})`/); assert.ok(match, text); return match[1]; }
async function state(runId) { return JSON.parse(await fs.readFile(path.join(root, 'workflow-jobs', runId, 'status.json'), 'utf8')); }
async function waitFor(runId, predicate, timeout = 15000) {
  const until = Date.now() + timeout;
  while (Date.now() < until) {
    const current = await state(runId);
    if (predicate(current)) return current;
    await tools.statusTool.execute({ runId }, context);
  }
  throw new Error(`Timed out: ${JSON.stringify(await state(runId))}`);
}
async function start(task) {
  const card = await tools.startTool.execute({ task }, context);
  const runId = runIdFrom(card); started.push(runId);
  assert.match(card, /QUEUED/); assert.doesNotMatch(card, /## LoKi: VERIFIED/);
  return runId;
}
async function finish(runId) { return waitFor(runId, current => TERMINAL_STATES.has(current.status)); }
async function test(name, body) {
  try { await body(); passed++; process.stdout.write(`PASS ${name}\n`); }
  catch (error) { process.stderr.write(`FAIL ${name}: ${error.stack}\n`); throw error; }
}

const fakeRunner = String.raw`
param([switch]$AutoPrepare,[string]$Workflow,[string]$InstallRoot,[string]$ProjectPath,[string]$TaskFile,[string]$ChecksFile,[string]$ProgressFile,[string]$RequestId)
$ErrorActionPreference='Stop'
$task=(Get-Content -LiteralPath $TaskFile -Raw).Trim()
$run=Join-Path $InstallRoot "runs/$RequestId"
New-Item -ItemType Directory -Path $run -Force | Out-Null
function Event([string]$phase,[string]$role,[string]$state,[string]$message) {
    @{time=[DateTime]::UtcNow.ToString('o');phase=$phase;role=$role;model='fixture/local';state=$state;message=$message;sessionId='fixture-child';tool='read';runPath=$run} | ConvertTo-Json -Compress | Add-Content -LiteralPath $ProgressFile -Encoding utf8
}
if (-not $AutoPrepare -or $Workflow -ne 'Auto' -or -not (Test-Path -LiteralPath $ChecksFile)) { throw 'Missing binding' }
Event 'prepare' 'shadow-planner' 'running' 'Preparing acceptance criteria'
Start-Sleep -Milliseconds 400
if ($task -eq 'cancel') {
    $chain=Get-Content -LiteralPath (Join-Path $InstallRoot 'toolchain.json') -Raw | ConvertFrom-Json
    $info=[Diagnostics.ProcessStartInfo]::new(); $info.FileName=$chain.nodeExecutable; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.ArgumentList.Add('-e'); $info.ArgumentList.Add('setTimeout(()=>{},60000)')
    $descendant=[Diagnostics.Process]::Start($info)
    Set-Content -LiteralPath (Join-Path (Split-Path $TaskFile -Parent) 'fixture-child-pid.txt') -Value $descendant.Id
    Event 'implementation' 'shadow-coder' 'running' 'Waiting for cancellation'
    Start-Sleep -Seconds 60
}
if ($task -eq 'missing') { Write-Output 'VERIFIED'; exit 0 }
Event 'review' 'shadow-reviewer' 'finished' 'Independent review complete'
Start-Sleep -Milliseconds 250
if ($task -eq 'success') {
    1..180 | ForEach-Object { Event 'implementation' 'shadow-coder' 'tool' 'Detailed tool activity' }
    @{time=[DateTime]::UtcNow.ToString('o');phase='prepare';role='shadow-planner';model='';sessionId='';state='passed';message='Preparation accepted'} | ConvertTo-Json -Compress | Add-Content -LiteralPath $ProgressFile -Encoding utf8
}
$status='VERIFIED'; $exit=0; $fingerprint=('a'*64); $errorText=$null; $request=$RequestId
if ($task -eq 'failed') { $status='NOT_VERIFIED'; $exit=1; $errorText='Fixture check failed' }
if ($task -eq 'unvalidated') { $status='REVIEWED_UNVALIDATED'; $exit=2 }
if ($task -eq 'needs-input') { $status='NOT_VERIFIED'; $exit=1; $errorText='NEEDS_INPUT: missing project information' }
if ($task -eq 'spoof') { $request='00000000-0000-4000-8000-000000000000' }
if ($task -eq 'fingerprint') { $fingerprint='' }
if ($task -eq 'wrong-exit') { $exit=1 }
$receipt=Join-Path $run 'receipt.json'
@{schema_version=2;request_id=$request;project=$ProjectPath;status=$status;final_fingerprint=$fingerprint;error=$errorText;rounds=@(@{status=$status;reasons=@('fixture evidence');checks=@(@{name='fixture-check';passed=$true})})} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receipt -Encoding utf8
Event 'validation' 'shadow-validator' 'finished' 'Tests checked'
Write-Output "Pruefbericht: $receipt"
exit $exit
`;

try {
  for (const dir of [path.join(root, 'app'), path.join(root, 'projects', 'one'), path.join(root, 'projects', 'two'), project, secondProject]) await fs.mkdir(dir, { recursive: true });
  for (const name of ['KiloWorkflowTools.mjs', 'WorkflowJob.mjs']) await fs.copyFile(path.join(source, name), path.join(root, 'app', name));
  const powerShell = spawnSync('pwsh', ['-NoLogo', '-NoProfile', '-Command', '(Get-Process -Id $PID).Path'], { encoding: 'utf8', shell: false, windowsHide: true });
  assert.equal(powerShell.status, 0, powerShell.error?.message || powerShell.stderr);
  await fs.writeFile(path.join(root, 'app', 'Invoke-ReviewedTask.ps1'), fakeRunner);
  const firstChecks = path.join(root, 'projects', 'one', 'checks.json');
  const secondChecks = path.join(root, 'projects', 'two', 'checks.json');
  await fs.writeFile(firstChecks, '{}'); await fs.writeFile(secondChecks, '{}');
  const registrations = [{ project, checks: firstChecks }, { project: secondProject, checks: secondChecks }];
  await fs.writeFile(path.join(root, 'workspaces.json'), JSON.stringify(registrations));
  await fs.writeFile(path.join(root, 'toolchain.json'), JSON.stringify({ nodeExecutable: process.execPath, powerShellExecutable: powerShell.stdout.trim() }));
  tools = createWorkflowTools({ installRoot: root, pollMilliseconds: 100 });

  await test('permission and child guards, fixed tool argument surface', async () => {
    assert.deepEqual(Object.keys(tools.startTool.args), ['task']);
    for (const name of ['statusTool', 'cancelTool', 'detailsTool']) assert.deepEqual(Object.keys(tools[name].args), ['runId']);
    await assert.rejects(tools.startTool.execute({ task: 'test' }, { directory: project }), /Werkzeugberechtigung/);
    await assert.rejects(tools.startTool.execute({ task: 'test' }, { ...context, ask: async () => { throw new Error('Denied by Kilo'); } }), /Denied by Kilo/);
    const previous = process.env.LOKI_WORKFLOW_CHILD;
    try {
      process.env.LOKI_WORKFLOW_CHILD = '1';
      for (const tool of Object.values(tools)) await assert.rejects(tool.execute({ task: 'test', runId: 'x' }, context), /Unteragent/);
    } finally { if (previous === undefined) delete process.env.LOKI_WORKFLOW_CHILD; else process.env.LOKI_WORKFLOW_CHILD = previous; }
    await assert.rejects(tools.startTool.execute({ task: 'x'.repeat(20001) }, context), /20000/);
    await assert.rejects(tools.startTool.execute({ task: '  ' }, context), /20000/);
    await assert.rejects(tools.startTool.execute({ task: 'test' }, { ...context, directory: fixture }), /registriert/);
    await assert.rejects(tools.statusTool.execute({ runId: '../outside' }, context), /Auftragskennung/);
    await assert.rejects(managedPath(root, path.join(fixture, 'elsewhere')), /ausserhalb/);
  });

  await test('visible phases, project lock, binding and verified receipt', async () => {
    const runId = await start('success');
    await assert.rejects(tools.startTool.execute({ task: 'parallel' }, context), /bereits ein LoKi-Auftrag/);
    await assert.rejects(tools.statusTool.execute({ runId }, { ...context, directory: secondProject }), /gehoert nicht/);
    const done = await finish(runId);
    assert.equal(done.status, 'VERIFIED', JSON.stringify(done)); assert.equal(done.exitCode, 0);
    assert.ok(done.phaseSummary.some(event => event.role === 'shadow-reviewer'));
    assert.ok(done.events.some(event => event.runPath && inside(path.join(root, 'runs'), event.runPath)), JSON.stringify(done));
    const card = await tools.statusTool.execute({ runId }, context);
    assert.ok(done.phaseSummary.some(event => event.role === 'shadow-preparer' || event.role === 'shadow-planner'));
    const preparation = done.phaseSummary.find(event => event.phase === 'prepare' && event.role === 'shadow-planner');
    assert.equal(preparation.state, 'passed');
    assert.equal(preparation.model, 'fixture/local');
    assert.equal(preparation.sessionId, 'fixture-child');
    assert.match(card, /shadow-planner/); assert.match(card, /shadow-reviewer/);
    assert.match(card, /shadow-validator/); assert.match(card, /fixture\/local/);
    const details = await tools.detailsTool.execute({ runId }, context);
    assert.match(details, /fixture evidence/); assert.match(details, /Pruefbericht/);
    assert.match(await fs.readFile(path.join(root, 'projects', 'one', 'LOKI-STATUS.md'), 'utf8'), /VERIFIED/);
  });

  for (const [task, expected] of [['failed', 'NOT_VERIFIED'], ['unvalidated', 'REVIEWED_UNVALIDATED'], ['needs-input', 'NEEDS_INPUT'], ['missing', 'FAILED'], ['spoof', 'FAILED'], ['fingerprint', 'NOT_VERIFIED'], ['wrong-exit', 'NOT_VERIFIED']]) {
    await test(`receipt gate ${task} -> ${expected}`, async () => { const done = await finish(await start(task)); assert.equal(done.status, expected, JSON.stringify(done)); });
  }

  await test('status abort keeps job running; explicit cancel stops owned process', async () => {
    const runId = await start('cancel');
    await waitFor(runId, current => current.events.some(event => event.role === 'shadow-coder'));
    const owner = (await state(runId)).workerPid;
    await assert.rejects(runJob(root, runId), /bereits einen Worker/);
    assert.equal((await state(runId)).workerPid, owner);
    assert.equal((await fs.readdir(path.join(root, 'workflow-jobs', 'locks'))).length, 1);
    assert.match(await tools.detailsTool.execute({ runId }, context), /Bericht liegt noch nicht vor/);
    const descendant = Number((await fs.readFile(path.join(root, 'workflow-jobs', runId, 'fixture-child-pid.txt'), 'utf8')).trim());
    const abort = new AbortController(); abort.abort();
    const before = Date.now();
    const status = await tools.statusTool.execute({ runId }, { ...context, abort: abort.signal });
    assert.ok(Date.now() - before < 1000); assert.match(status, /RUNNING/);
    assert.equal((await state(runId)).status, 'RUNNING');
    assert.match(await tools.cancelTool.execute({ runId }, context), /Abbruch/);
    const done = await finish(runId); assert.equal(done.status, 'CANCELLED', JSON.stringify(done));
    assert.throws(() => process.kill(descendant, 0), error => error.code === 'ESRCH', 'Own descendant must also be stopped');
    assert.equal((await fs.readdir(path.join(root, 'workflow-jobs', 'locks'))).length, 0);
    assert.match(await tools.cancelTool.execute({ runId }, context), /CANCELLED/);
  });

  await test('stale worker requires recovery, keeps unknown job cancellable', async () => {
    const runId = '00000000-0000-4000-8000-000000000001';
    const request = { schemaVersion: 1, runId, project, checksFile: firstChecks, stateDirectory: path.dirname(firstChecks), createdUtc: '2000-01-01T00:00:00.000Z' };
    const stale = { schemaVersion: 1, runId, status: 'RUNNING', updatedUtc: request.createdUtc, heartbeatUtc: request.createdUtc, events: [] };
    assert.equal(stateView(stale, request).status, 'WORKER_UNRESPONSIVE');
    assert.equal(stateView({ ...stale, heartbeatUtc: new Date().toISOString() }, request).status, 'RUNNING');
    const job = path.join(root, 'workflow-jobs', runId); await fs.mkdir(job);
    await fs.writeFile(path.join(job, 'request.json'), JSON.stringify(request));
    await fs.writeFile(path.join(job, 'status.json'), JSON.stringify(stale));
    assert.match(await tools.statusTool.execute({ runId }, context), /WORKER_UNRESPONSIVE/);
    assert.match(await tools.cancelTool.execute({ runId }, context), /Abbruch/);
    assert.equal((await fs.stat(path.join(job, 'cancel'))).isFile(), true);
  });

  await test('state symlinks and duplicate registrations rejected', async () => {
    const link = path.join(root, 'linked-state');
    await fs.symlink(path.join(root, 'projects', 'one'), link, process.platform === 'win32' ? 'junction' : 'dir');
    await assert.rejects(managedPath(root, path.join(link, 'checks.json')), /Verknuepfungen/);
    await fs.writeFile(path.join(root, 'workspaces.json'), JSON.stringify([...registrations, registrations[0]]));
    await assert.rejects(tools.startTool.execute({ task: 'test' }, context), /eindeutig registriert/);
    await fs.writeFile(path.join(root, 'workspaces.json'), JSON.stringify(registrations));
  });
  assert.ok(['loki_start', 'loki_status', 'loki_cancel', 'loki_details'].every(permission => calls.includes(permission)));
  process.stdout.write(`${passed} workflow tool integration tests passed.\n`);
} finally {
  if (tools) {
    for (const runId of started) {
      try {
        if (!TERMINAL_STATES.has((await state(runId)).status)) { await tools.cancelTool.execute({ runId }, context); await finish(runId); }
      } catch (error) { process.stderr.write(`Fixture cleanup warning: ${error.message}\n`); }
    }
  }
  const resolved = path.resolve(fixture);
  if (path.dirname(resolved) !== temporaryBase || !path.basename(resolved).startsWith('loki-workflow-tools-')) throw new Error('Unsafe fixture cleanup target');
  await fs.rm(resolved, { recursive: true, force: true, maxRetries: 40, retryDelay: 100 });
}
