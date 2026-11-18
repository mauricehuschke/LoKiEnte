// Local Kilo custom tools. No SDK, network dependency or import-time side effects.
import { promises as fs } from 'node:fs';
import { spawn } from 'node:child_process';
import { randomUUID, createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// WORKER_UNRESPONSIVE ends automatic polling, not the unknown underlying job.
export const TERMINAL_STATES = new Set(['VERIFIED', 'NOT_VERIFIED', 'REVIEWED_UNVALIDATED', 'NEEDS_INPUT', 'FAILED', 'CANCELLED', 'WORKER_UNRESPONSIVE']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const normalized = value => process.platform === 'win32' ? path.resolve(value).toLowerCase() : path.resolve(value);
export const samePath = (a, b) => typeof a === 'string' && typeof b === 'string' && normalized(a) === normalized(b);
export const inside = (root, candidate) => normalized(candidate).startsWith(normalized(root) + path.sep);

export async function managedPath(root, candidate, { missing = false } = {}) {
  const absolute = path.resolve(candidate);
  if (!inside(root, absolute)) throw new Error('Path is outside managed LoKiEnte files.');
  let cursor = path.resolve(root);
  for (const part of path.relative(root, absolute).split(path.sep)) {
    cursor = path.join(cursor, part);
    try {
      if ((await fs.lstat(cursor)).isSymbolicLink()) throw new Error('Links in managed task paths are not allowed.');
    } catch (error) {
      if (!(missing && error.code === 'ENOENT')) throw error;
    }
  }
  return absolute;
}

export async function readJson(file, limit = 1024 * 1024) {
  const info = await fs.lstat(file);
  if (!info.isFile() || info.isSymbolicLink() || info.size > limit) throw new Error('Invalid or oversized LoKiEnte state file.');
  return JSON.parse(await fs.readFile(file, 'utf8'));
}

export async function replaceFile(temporary, file) {
  for (let attempt = 0; ; attempt++) {
    try { await fs.rename(temporary, file); return; }
    catch (error) {
      // Windows scanners/readers can briefly deny replacement. Preserve the
      // previous complete file and retry; never delete it to force a rename.
      if (attempt >= 12 || !['EPERM', 'EACCES', 'EBUSY'].includes(error.code)) throw error;
      await delay(25 * (attempt + 1));
    }
  }
}

export async function writeJson(file, value) {
  const temporary = `${file}.${randomUUID()}.tmp`;
  try {
    await fs.writeFile(temporary, JSON.stringify(value, null, 2), { encoding: 'utf8', flag: 'wx' });
    await replaceFile(temporary, file);
  } finally { await fs.unlink(temporary).catch(() => {}); }
}

export async function registeredProject(root, directory) {
  if (typeof directory !== 'string' || !path.isAbsolute(directory)) throw new Error('Kilo must be open in a registered project.');
  const real = await fs.realpath(directory);
  if (!samePath(real, directory)) throw new Error('Project links are not used for the write workflow.');
  const index = await readJson(await managedPath(root, path.join(root, 'workspaces.json')));
  if (!Array.isArray(index)) throw new Error('Invalid workspace index.');
  const matches = [];
  for (const item of index) {
    if (!item || typeof item.project !== 'string' || !path.isAbsolute(item.project)) continue;
    if (samePath(item.project, real)) matches.push(item);
  }
  if (matches.length !== 1) throw new Error('Project is not uniquely registered. Open it through the LoKiEnte shortcut or rerun provisioning.');
  const entry = matches[0];
  const checks = await managedPath(root, entry.checks, { missing: true });
  if (!inside(path.join(root, 'projects'), checks) || path.basename(checks) !== 'checks.json') throw new Error('Project has no valid managed check path.');
  const stateDirectory = path.dirname(checks);
  if (!(await fs.stat(stateDirectory)).isDirectory()) throw new Error('Managed project directory missing.');
  return { project: real, checksFile: checks, stateDirectory };
}

export function lockName(project) { return createHash('sha256').update(normalized(project)).digest('hex') + '.json'; }

export async function jobPaths(root, runId) {
  if (typeof runId !== 'string' || !UUID.test(runId)) throw new Error('Invalid LoKiEnte task identifier.');
  const job = await managedPath(root, path.join(root, 'workflow-jobs', runId));
  return { job, request: await managedPath(root, path.join(job, 'request.json')), status: await managedPath(root, path.join(job, 'status.json')) };
}

export async function releaseProjectLock(root, request) {
  const lock = await managedPath(root, path.join(root, 'workflow-jobs', 'locks', lockName(request.project)), { missing: true });
  try { if ((await readJson(lock)).runId === request.runId) await fs.unlink(lock); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
}

function cell(value) { return String(value ?? '').replace(/[\r\n|]/g, ' ').replace(/`/g, "'").slice(0, 180); }
export function stateView(state, request, now = Date.now()) {
  if (state.schemaVersion !== 1 || state.runId !== request.runId || typeof state.status !== 'string') throw new Error('Invalid task status.');
  const heartbeat = Date.parse(state.heartbeatUtc || state.updatedUtc || request.createdUtc);
  if (!TERMINAL_STATES.has(state.status) && (!Number.isFinite(heartbeat) || now - heartbeat > (state.status === 'QUEUED' ? 30000 : 120000))) {
    return { ...state, status: 'WORKER_UNRESPONSIVE', summary: 'No current worker response. It is unknown whether processes are still running. The project lock remains; do not start another task or blindly remove a lock. Check local job logs and processes; recover only after confirmed process exit or a system restart. Another loki_status may show a recovered worker; loki_cancel can still record a cancellation request.' };
  }
  return state;
}

export function renderStatus(state, request) {
  const lines = [`## LoKiEnte: ${cell(state.status)}`, '', `Task: \`${request.runId}\``, `Project: ${cell(request.project)}`, ''];
  const phases = new Map();
  for (const event of state.phaseSummary ?? state.events ?? []) {
    const key = `${event.phase ?? 'Workflow'}\0${event.role ?? ''}`;
    phases.set(key, event);
  }
  if (phases.size) {
    lines.push('| Phase | Agent | Model | State |', '|---|---|---|---|');
    for (const event of [...phases.values()].slice(-40)) lines.push(`| ${cell(event.phase)} | ${cell(event.role)} | ${cell(event.model)} | ${cell(event.state)} |`);
    lines.push('');
  }
  const last = (state.events ?? []).at(-1);
  if (last?.message) lines.push(cell(last.message), '');
  if (last?.tool) lines.push(`Tool: ${cell(last.tool)}`, '');
  if (state.summary) lines.push(String(state.summary).slice(0, 4000), '');
  if (state.receiptPath) lines.push(`Verification report: ${state.receiptPath}`, '');
  lines.push(`Live report in the project task directory: ${path.join(request.stateDirectory, 'LOKI-STATUS.md')}`);
  if (!TERMINAL_STATES.has(state.status)) lines.push('', 'The task is still running. Follow loki_status with the same runId until completion. Cancelling a status query does not stop the task; use loki_cancel for that.');
  return lines.join('\n');
}

async function authorize(context, permission) {
  if (process.env.LOKI_WORKFLOW_CHILD === '1') throw new Error('A workflow subagent must not start or control another LoKiEnte task.');
  if (typeof context?.ask !== 'function') throw new Error('Kilo does not provide verifiable tool authorization.');
  await context.ask({ permission, patterns: ['*'], always: ['*'], metadata: { purpose: 'Local reviewed development task' } });
}

async function toolchain(root) {
  const chain = await readJson(await managedPath(root, path.join(root, 'toolchain.json')));
  for (const [key, expected] of [['nodeExecutable', /^node(?:\.exe)?$/i], ['powerShellExecutable', /^pwsh(?:\.exe)?$/i]]) {
    if (typeof chain[key] !== 'string' || !path.isAbsolute(chain[key]) || !expected.test(path.basename(chain[key])) || !(await fs.stat(chain[key])).isFile()) throw new Error(`Provisioned tool missing: ${key}`);
  }
  return chain;
}

export function createWorkflowTools({ installRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'), pollMilliseconds = 30000 } = {}) {
  if (!Number.isInteger(pollMilliseconds) || pollMilliseconds < 0 || pollMilliseconds > 30000) throw new Error('Invalid status timeout.');
  async function bind(context) {
    const root = await fs.realpath(installRoot);
    return { root, entry: await registeredProject(root, context?.directory) };
  }
  async function load(runId, context) {
    const { root, entry } = await bind(context);
    const paths = await jobPaths(root, runId);
    const request = await readJson(paths.request);
    if (request.schemaVersion !== 1 || request.runId !== runId || !samePath(request.project, entry.project) || !samePath(request.checksFile, entry.checksFile) || !samePath(request.stateDirectory, entry.stateDirectory)) throw new Error('Task does not belong to this registered project.');
    return { root, entry, paths, request, state: stateView(await readJson(paths.status, 2 * 1024 * 1024), request) };
  }
  const startTool = {
    description: 'Starts a local development task from the complete user request: automatic check configuration, test author, independent reviews, checks. Then call loki_status until the task reaches a final status. No arbitrary shell commands or project paths.',
    args: { task: { type: 'string', minLength: 1, maxLength: 20000, description: 'Complete functional user request including boundaries and requirements.' } },
    async execute({ task }, context) {
      await authorize(context, 'loki_start');
      if (typeof task !== 'string' || !task.trim() || task.length > 20000) throw new Error('Task must contain 1 to 20000 characters.');
      const { root, entry } = await bind(context);
      const chain = await toolchain(root);
      const worker = await managedPath(root, path.join(root, 'app', 'WorkflowJob.mjs'));
      await managedPath(root, path.join(root, 'app', 'Invoke-ReviewedTask.ps1'));
      const jobs = await managedPath(root, path.join(root, 'workflow-jobs'), { missing: true });
      const locks = await managedPath(root, path.join(jobs, 'locks'), { missing: true });
      await fs.mkdir(locks, { recursive: true });
      const lock = path.join(locks, lockName(entry.project));
      const runId = randomUUID();
      try { await fs.writeFile(lock, JSON.stringify({ runId, project: entry.project }), { flag: 'wx' }); }
      catch (error) {
        if (error.code !== 'EEXIST') throw error;
        const owner = await readJson(lock);
        throw new Error(`A LoKiEnte task is already registered for this project: ${owner.runId}. Check its status; do not start a parallel run.`);
      }
      const request = { schemaVersion: 1, runId, ...entry, createdUtc: new Date().toISOString(), parentSessionId: typeof context.sessionID === 'string' ? context.sessionID : null };
      const job = path.join(jobs, runId);
      try {
        await fs.mkdir(job);
        await fs.writeFile(path.join(job, 'task.md'), task, { encoding: 'utf8', flag: 'wx' });
        await writeJson(path.join(job, 'request.json'), request);
        const initial = { schemaVersion: 1, runId, status: 'QUEUED', updatedUtc: new Date().toISOString(), events: [], summary: 'Task accepted; preparation starting.' };
        await writeJson(path.join(job, 'status.json'), initial);
        const env = { ...process.env };
        delete env.NODE_OPTIONS; delete env.BUN_OPTIONS; delete env.KILO_CONFIG_CONTENT;
        const child = spawn(chain.nodeExecutable, [worker, '--root', root, '--run-id', runId], { cwd: entry.project, env, detached: true, windowsHide: true, stdio: 'ignore', shell: false });
        await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
        child.unref();
        return renderStatus(initial, request);
      } catch (error) {
        await writeJson(path.join(job, 'status.json'), { schemaVersion: 1, runId, status: 'FAILED', updatedUtc: new Date().toISOString(), summary: `Startup failed: ${error.message}`, events: [] }).catch(() => {});
        await releaseProjectLock(root, request);
        throw error;
      }
    },
  };
  const statusTool = {
    description: 'Shows actual phases, agents, models and test results of a LoKiEnte task; waits up to 30 seconds for progress. Keep calling until the task reaches a final status.',
    args: { runId: { type: 'string', description: 'Task identifier from loki_start.' } },
    async execute({ runId }, context) {
      await authorize(context, 'loki_status');
      const loaded = await load(runId, context);
      const version = loaded.state.updatedUtc;
      const until = Date.now() + pollMilliseconds;
      while (!TERMINAL_STATES.has(loaded.state.status) && Date.now() < until && !context.abort?.aborted) {
        await delay(Math.min(250, Math.max(1, until - Date.now())));
        loaded.state = stateView(await readJson(loaded.paths.status, 2 * 1024 * 1024), loaded.request);
        if (loaded.state.updatedUtc !== version) break;
      }
      return renderStatus(loaded.state, loaded.request);
    },
  };
  const cancelTool = {
    description: 'Requests cancellation of this LoKiEnte task at the explicit user request. The worker stops only its own process tree; code is not rolled back.',
    args: { runId: { type: 'string', description: 'Identifier of the owned task to cancel.' } },
    async execute({ runId }, context) {
      await authorize(context, 'loki_cancel');
      const loaded = await load(runId, context);
      if (TERMINAL_STATES.has(loaded.state.status) && loaded.state.status !== 'WORKER_UNRESPONSIVE') return renderStatus(loaded.state, loaded.request);
      await fs.writeFile(await managedPath(loaded.root, path.join(loaded.paths.job, 'cancel'), { missing: true }), 'cancel\n', { flag: 'wx' }).catch(error => { if (error.code !== 'EEXIST') throw error; });
      return `Cancellation requested for ${runId}. Status becomes CANCELLED only after the process tree exits. Confirm with loki_status. Existing changes are preserved for review.`;
    },
  };
  const detailsTool = {
    description: 'Reads the bounded verification report and recent events of the LoKiEnte task bound to this project. No arbitrary file paths.',
    args: { runId: { type: 'string', description: 'Task identifier.' } },
    async execute({ runId }, context) {
      await authorize(context, 'loki_details');
      const loaded = await load(runId, context);
      const lines = [renderStatus(loaded.state, loaded.request), '', '### Letzte Ereignisse', '```json', JSON.stringify((loaded.state.events ?? []).slice(-30), null, 2), '```'];
      if (loaded.state.receiptPath) {
        const receiptFile = await managedPath(loaded.root, loaded.state.receiptPath);
        if (!inside(path.join(loaded.root, 'runs'), receiptFile)) throw new Error('Invalid report path.');
        const receipt = await readJson(receiptFile, 16 * 1024 * 1024);
        if (receipt.request_id !== runId || !samePath(receipt.project, loaded.entry.project)) throw new Error('Verification report does not belong to this task.');
        const final = receipt.rounds?.at(-1);
        const summary = { status: receipt.status, error: receipt.error, acceptanceCriteria: receipt.acceptance_criteria, preparationReview: receipt.preparation_review, reasons: final?.reasons, changeTypes: final?.change_types, checks: final?.checks, review: final?.review?.Verdict, validation: final?.validation?.Verdict, specialists: final?.specialists };
        lines.push('', '### Verification result', '```json', JSON.stringify(summary, null, 2).slice(0, 20000), '```');
      } else {
        lines.push('', 'No final verified report is available yet.');
      }
      for (const filename of ['worker.stdout.log', 'worker.stderr.log']) {
        const logFile = await managedPath(loaded.root, path.join(loaded.paths.job, filename), { missing: true });
        let handle;
        try {
          const info = await fs.lstat(logFile);
          if (!info.isFile() || info.isSymbolicLink()) throw new Error('Invalid job log path.');
          handle = await fs.open(logFile, 'r');
          const buffer = Buffer.alloc(Math.min(info.size, 4096));
          const { bytesRead } = await handle.read(buffer, 0, buffer.length, Math.max(0, info.size - buffer.length));
          if (bytesRead) lines.push('', `### ${filename} (letzte maximal 4096 Bytes)`, '```text', buffer.subarray(0, bytesRead).toString('utf8').replace(/```/g, "'''"), '```');
        } catch (error) { if (error.code !== 'ENOENT') throw error; }
        finally { await handle?.close(); }
      }
      return lines.join('\n');
    },
  };
  return { startTool, statusTool, cancelTool, detailsTool };
}

export const { startTool, statusTool, cancelTool, detailsTool } = createWorkflowTools();
