// Detached local worker for a single explicitly requested Kilo workflow.
import { promises as fs } from 'node:fs';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { StringDecoder } from 'node:string_decoder';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { inside, jobPaths, lockName, managedPath, readJson, registeredProject, releaseProjectLock, renderStatus, replaceFile, samePath, writeJson } from './KiloWorkflowTools.mjs';

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const maxLogBytes = 16 * 1024 * 1024;
function createEventReader(file, root) {
  let position = 0, carry = '';
  const decoder = new StringDecoder('utf8');
  return async function readEvents() {
  try {
    const info = await fs.lstat(file);
    if (!info.isFile() || info.isSymbolicLink()) throw new Error('Invalid progress log.');
    if (info.size < position) throw new Error('Progress log was unexpectedly truncated.');
    const handle = await fs.open(file, 'r');
    let tail;
    try {
      const buffer = Buffer.alloc(Math.min(info.size - position, 256 * 1024));
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, position);
      position += bytesRead;
      tail = carry + decoder.write(buffer.subarray(0, bytesRead));
    } finally { await handle.close(); }
    const lines = tail.split(/\r?\n/);
    carry = lines.pop();
    if (carry.length > 16384) throw new Error('Progress event is too large.');
    const result = [];
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const input = JSON.parse(line);
        const event = {};
        for (const field of ['time', 'phase', 'role', 'model', 'state', 'message', 'sessionId', 'tool']) {
          if (typeof input[field] === 'string') event[field] = input[field].slice(0, field === 'message' ? 1000 : 250);
        }
        for (const field of ['runPath', 'receiptPath']) {
          if (typeof input[field] === 'string' && inside(path.join(root, 'runs'), input[field])) {
            event[field] = await managedPath(root, input[field], { missing: true });
          }
        }
        if (event.phase || event.role || event.message) result.push(event);
      } catch { /* Malformed or unsafe events are data, never instructions. */ }
    }
    return { events: result, more: position < info.size };
  } catch (error) { if (error.code === 'ENOENT') return { events: [], more: false }; throw error; }
  };
}

async function stopOwnedChild(child) {
  if (child.exitCode !== null || child.signalCode !== null || !Number.isInteger(child.pid)) return;
  if (process.platform === 'win32') {
    const taskkill = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'taskkill.exe');
    const killer = spawn(taskkill, ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, shell: false, stdio: ['ignore', 'ignore', 'pipe'] });
    let diagnostic = '';
    killer.stderr.on('data', chunk => { diagnostic = (diagnostic + chunk.toString('utf8')).slice(-1000); });
    await new Promise((resolve, reject) => {
      killer.once('close', code => { if (code === 0 || child.exitCode !== null || child.signalCode !== null) resolve(); else reject(new Error(`Could not terminate owned process tree (taskkill ${code}): ${diagnostic.trim()}`)); });
      killer.once('error', reject);
    });
  } else { child.kill('SIGTERM'); }
}

export async function runJob(root, runId) {
  root = await fs.realpath(root);
  const paths = await jobPaths(root, runId);
  const request = await readJson(paths.request);
  const entry = await registeredProject(root, request.project);
  if (request.schemaVersion !== 1 || request.runId !== runId || !samePath(request.project, entry.project) || !samePath(request.checksFile, entry.checksFile) || !samePath(request.stateDirectory, entry.stateDirectory)) throw new Error('Task binding is invalid.');
  const projectLock = await readJson(await managedPath(root, path.join(root, 'workflow-jobs', 'locks', lockName(entry.project))));
  if (projectLock.runId !== runId || !samePath(projectLock.project, entry.project)) throw new Error('Task does not own the project lock.');
  const claim = await managedPath(root, path.join(paths.job, 'worker.claim.json'), { missing: true });
  try { await fs.writeFile(claim, JSON.stringify({ runId, workerPid: process.pid, createdUtc: new Date().toISOString() }), { flag: 'wx' }); }
  catch (error) { if (error.code === 'EEXIST') throw new Error('This task already has a worker. Status and project lock remain unchanged.'); throw error; }
  let state = { schemaVersion: 1, runId, status: 'RUNNING', workerPid: process.pid, updatedUtc: new Date().toISOString(), heartbeatUtc: new Date().toISOString(), events: [], phaseSummary: [], summary: 'Automatic task preparation is running.' };
  let child, finished = false, cancelled = false, exitCode = null, receiptPath = '', stdoutTail = '', stdoutBytes = 0, stderrBytes = 0;
  let cancelAttemptAt = 0, cancelError = '';
  let outHandle, errHandle, closed, processError, streamError;
  let streamWrites = Promise.resolve();
  const output = path.join(paths.job, 'worker.stdout.log');
  const errors = path.join(paths.job, 'worker.stderr.log');
  const eventsFile = await managedPath(root, path.join(paths.job, 'events.jsonl'), { missing: true });
  const liveFile = await managedPath(root, path.join(entry.stateDirectory, 'LOKI-STATUS.md'), { missing: true });
  const phases = new Map();
  const readEvents = createEventReader(eventsFile, root);
  function applyEvents(events) {
    state.events = [...state.events, ...events].slice(-120);
    for (const event of events) {
      const key = `${event.phase ?? 'workflow'}\0${event.role ?? ''}`;
      const activity = ['tool', 'activity'].includes(event.state);
      if (!activity || !phases.has(key)) {
        const previous = phases.get(key);
        phases.set(key, {
          ...event,
          state: activity ? 'running' : event.state,
          model: event.model?.trim() ? event.model : previous?.model ?? '',
          sessionId: event.sessionId?.trim() ? event.sessionId : previous?.sessionId ?? '',
        });
      }
      if (phases.size > 40) phases.delete(phases.keys().next().value);
    }
    state.phaseSummary = [...phases.values()];
  }
  async function publish(releaseLock = false) {
    state.updatedUtc = new Date().toISOString();
    state.heartbeatUtc = state.updatedUtc;
    const temporary = liveFile + `.${randomUUID()}.tmp`;
    try { await fs.writeFile(temporary, renderStatus(state, request), { encoding: 'utf8', flag: 'wx' }); await replaceFile(temporary, liveFile); }
    finally { await fs.unlink(temporary).catch(() => {}); }
    if (releaseLock) await releaseProjectLock(root, request);
    await writeJson(paths.status, state);
  }
  try {
    await publish();
    const chain = await readJson(await managedPath(root, path.join(root, 'toolchain.json')));
    if (typeof chain.powerShellExecutable !== 'string' || !path.isAbsolute(chain.powerShellExecutable) || !/^pwsh(?:\.exe)?$/i.test(path.basename(chain.powerShellExecutable))) throw new Error('Provisioned PowerShell missing.');
    const runner = await managedPath(root, path.join(root, 'app', 'Invoke-ReviewedTask.ps1'));
    const taskFile = await managedPath(root, path.join(paths.job, 'task.md'));
    outHandle = await fs.open(output, 'wx'); errHandle = await fs.open(errors, 'wx');
    const args = ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', runner, '-AutoPrepare', '-Workflow', 'Auto', '-InstallRoot', root, '-ProjectPath', entry.project, '-TaskFile', taskFile, '-ChecksFile', entry.checksFile, '-ProgressFile', eventsFile, '-RequestId', runId];
    const env = { ...process.env };
    delete env.NODE_OPTIONS; delete env.BUN_OPTIONS; delete env.KILO_CONFIG_CONTENT;
    child = spawn(chain.powerShellExecutable, args, { cwd: entry.project, env, shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.on('data', chunk => {
      stdoutBytes += chunk.length;
      if (stdoutBytes <= maxLogBytes) streamWrites = streamWrites.then(() => outHandle.write(chunk)).catch(error => { streamError = error; });
      stdoutTail = (stdoutTail + chunk.toString('utf8')).slice(-65536);
      for (const match of stdoutTail.matchAll(/(?:^|\r?\n)Verification report: ([^\r\n]+)/g)) receiptPath = match[1].trim();
    });
    child.stderr.on('data', chunk => {
      stderrBytes += chunk.length;
      if (stderrBytes <= maxLogBytes) streamWrites = streamWrites.then(() => errHandle.write(chunk)).catch(error => { streamError = error; });
    });
    closed = new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('close', code => { exitCode = code; finished = true; resolve(); });
    });
    // Attach rejection immediately; errors become state, never an orphan rejection.
    closed.catch(error => { processError = error; finished = true; });
    while (!finished) {
      if (streamError) throw streamError;
      const { events } = await readEvents();
      if (events.length) { applyEvents(events); await publish(); }
      else if (Date.now() - Date.parse(state.heartbeatUtc) >= 10000) {
        state.heartbeatUtc = new Date().toISOString();
        await writeJson(paths.status, state);
      }
      if ((!cancelled || cancelError) && Date.now() >= cancelAttemptAt && await fs.lstat(path.join(paths.job, 'cancel')).then(info => !info.isSymbolicLink() && info.isFile(), () => false)) {
        cancelled = true;
        state.status = 'CANCELLING'; state.summary = 'Cancellation requested; terminating owned process tree.';
        await publish();
        try { await stopOwnedChild(child); cancelError = ''; }
        catch (error) {
          cancelError = error.message;
          state.summary = `Cancellation not yet confirmed. ${cancelError} The task may still be running; the project lock remains active.`;
          await publish();
        }
        cancelAttemptAt = Date.now() + 5000;
      }
      await pause(200);
    }
    await closed.catch(() => {}); await streamWrites;
    if (processError || streamError) throw processError || streamError;
    let remaining;
    do { remaining = await readEvents(); applyEvents(remaining.events); } while (remaining.more);
    state.exitCode = exitCode;
    if (cancelled) {
      state.status = 'CANCELLED';
      state.summary = cancelError ? 'Cancellation was requested; the process has now exited. Automatic cancellation was blocked, so the task may have continued until now. Review changes manually.' : 'Task cancelled. Written files are preserved for manual diff review.';
    }
    else {
      if (!receiptPath) throw new Error('Runner returned no verification report; verification is impossible.');
      const receiptFile = await managedPath(root, receiptPath);
      if (!inside(path.join(root, 'runs'), receiptFile) || path.basename(receiptFile) !== 'receipt.json') throw new Error('Runner returned an invalid report path.');
      const receipt = await readJson(receiptFile, maxLogBytes);
      if (receipt.request_id !== runId || !samePath(receipt.project, request.project)) throw new Error('Verification report is not bound to this task.');
      state.receiptPath = receiptFile;
      if (exitCode === 0 && receipt.status === 'VERIFIED' && /^[a-f0-9]{64}$/.test(receipt.final_fingerprint ?? '') && receipt.rounds?.at(-1)?.status === 'VERIFIED') state.status = 'VERIFIED';
      else if (exitCode === 2 && receipt.status === 'REVIEWED_UNVALIDATED') state.status = 'REVIEWED_UNVALIDATED';
      else if (receipt.status === 'NEEDS_INPUT' || String(receipt.error ?? '').startsWith('NEEDS_INPUT:')) state.status = 'NEEDS_INPUT';
      else state.status = 'NOT_VERIFIED';
      state.summary = receipt.error || (state.status === 'VERIFIED' ? 'All required checks passed. Review the Git diff and functional behavior before committing.' : (receipt.rounds?.at(-1)?.reasons ?? []).join('\n') || 'The task was not verified. Read details in the verification report.');
    }
  } catch (error) {
    if (child && !finished) {
      // Do not publish a terminal state or release the project lock while a
      // child may still change files. A failed stop leaves the lock in place.
      try { await stopOwnedChild(child); }
      catch (stopError) {
        state.status = 'CANCELLING';
        state.summary = `Workflow error: ${error.message} Cancellation not yet confirmed: ${stopError.message} The project lock remains active.`;
        await publish();
      }
      await closed?.catch(() => {});
    }
    state.status = cancelled ? 'CANCELLED' : 'FAILED'; state.summary = `Workflow not verified: ${error.message}`;
  } finally {
    await streamWrites;
    await outHandle?.close().catch(() => {}); await errHandle?.close().catch(() => {});
    if (!child || finished) await publish(true);
  }
  return state;
}

if (process.argv[1] && samePath(process.argv[1], fileURLToPath(import.meta.url))) {
  const args = process.argv.slice(2);
  if (args.length !== 4 || args[0] !== '--root' || args[2] !== '--run-id') process.exitCode = 2;
  else runJob(args[1], args[3]).catch(async error => {
    // A worker that never acquired ownership must not overwrite the status or
    // release a lock owned by another instance. A stale job is exposed by the
    // status tool's heartbeat check and requires explicit local recovery.
    process.stderr.write(`Workflow startup failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
