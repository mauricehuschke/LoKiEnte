'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const { redact, loopback, readJsonResponse, LogTail } = require('./diagnostics.cjs');
const { waitForKilo, installedKilo } = require('./kilo-startup.cjs');
const { prepareAcceptanceProject } = require('./acceptance-project.cjs');
const { verifyAcceptanceConfiguration } = require('./acceptance-configuration.cjs');

async function withDeadline(action, milliseconds, message, signal) {
    let timer;
    try {
        if (signal?.aborted) throw cancellationError(signal);
        const pending = Promise.race([Promise.resolve().then(action), new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(message)), milliseconds); timer.unref?.(); })]);
        return await (signal ? withCancellation(() => pending, signal) : pending);
    }
    finally { clearTimeout(timer); }
}

async function waitForWorkspaceTrust(vscode, logger, timeoutMs = 600000, signal) {
    if (signal?.aborted) throw cancellationError(signal);
    if (vscode.workspace.isTrusted) return;
    logger.warn('VS Code', 'Waiting for you to trust the generated acceptance workspace in the VS Code Workspace Trust dialog.');
    await new Promise((resolve, reject) => {
        let subscription, settled = false;
        const finish = error => { if (settled) return; settled = true; clearTimeout(timer); subscription?.dispose(); signal?.removeEventListener('abort', abort); error ? reject(error) : resolve(); };
        const timer = setTimeout(() => finish(Object.assign(new Error('Workspace trust was not granted before the acceptance deadline. No trust setting was changed.'), { blocked: true })), timeoutMs);
        const abort = () => finish(cancellationError(signal)); signal?.addEventListener('abort', abort, { once: true });
        subscription = vscode.workspace.onDidGrantWorkspaceTrust(() => finish());
        if (vscode.workspace.isTrusted) finish();
        void vscode.window.showWarningMessage('LoKiEnte acceptance is waiting for Workspace Trust. Review and trust this generated test workspace in VS Code to continue.', 'Manage Workspace Trust', 'Cancel acceptance')
            .then(async answer => {
                if (answer === 'Cancel acceptance') finish(Object.assign(new Error('Acceptance cancelled while waiting for Workspace Trust.'), { blocked: true }));
                else if (!settled && answer === 'Manage Workspace Trust') await vscode.commands.executeCommand('workbench.trust.manage');
            }).catch(error => finish(error));
    });
    if (!vscode.workspace.isTrusted) throw Object.assign(new Error('Workspace trust is still unavailable.'), { blocked: true });
}

function cancellationError(signal) {
    return Object.assign(new Error(signal?.reason?.message || 'Acceptance was cancelled. No successful result was assumed.'), { blocked: true, code: 'LOKIENTE_ACCEPTANCE_CANCELLED' });
}

async function withCancellation(action, signal) {
    if (signal.aborted) throw cancellationError(signal);
    let abort;
    try { return await Promise.race([Promise.resolve().then(action), new Promise((_, reject) => { abort = () => reject(cancellationError(signal)); signal.addEventListener('abort', abort, { once: true }); })]); }
    finally { signal.removeEventListener('abort', abort); }
}

function runNative(file, args, { cwd, env = process.env, timeoutMs = 120000, signal } = {}) {
    if (signal?.aborted) return Promise.reject(cancellationError(signal));
    return new Promise((resolve, reject) => {
        const started = Date.now();
        const child = spawn(file, args, { cwd, env, shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let stdout = '', stderr = '', settled = false;
        const finish = (error, value) => {
            if (settled) return; settled = true; clearTimeout(timer); signal?.removeEventListener('abort', abort);
            if (error) { error.nativeResult = { code: child.exitCode, stdout, stderr, durationMs: Date.now() - started }; child.stdout.destroy(); child.stderr.destroy(); reject(error); } else resolve(value);
        };
        const timer = setTimeout(() => {
            if (child.exitCode === null) child.kill();
            finish(Object.assign(new Error(`Command deadline exceeded: ${path.basename(file)} (${child.exitCode === null ? 'process still running' : 'output remained open after process exit'}). No successful result was assumed.`), { code: 'LOKIENTE_NATIVE_TIMEOUT', processExited: child.exitCode !== null }));
        }, timeoutMs);
        const abort = () => { if (child.exitCode === null) child.kill(); finish(cancellationError(signal)); };
        signal?.addEventListener('abort', abort, { once: true });
        child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
        child.stdout.on('data', text => { stdout += text; if (stdout.length > 6 * 1024 * 1024) { child.kill(); finish(new Error('Command output limit exceeded.')); } });
        child.stderr.on('data', text => { stderr += text; if (stderr.length > 2 * 1024 * 1024) { child.kill(); finish(new Error('Command error output limit exceeded.')); } });
        child.once('error', error => finish(new Error(`Cannot start ${path.basename(file)}: ${error.code || error.message}`)));
        child.once('close', code => finish(null, { code, stdout, stderr }));
    });
}

function inspectKiloEvents(stdout, marker, file) {
    const events = stdout.split(/\r?\n/).filter(Boolean).map(line => JSON.parse(line));
    const equalPath = value => typeof value === 'string' && path.resolve(value).toLowerCase() === path.resolve(file).toLowerCase();
    const read = events.some(e => e.type === 'tool_use' && e.part?.tool === 'read' && e.part.state?.status === 'completed' && equalPath(e.part.state.input?.filePath) && e.part.state.output?.includes(marker));
    const reply = events.filter(e => e.type === 'text').map(e => e.part?.text || '').join('');
    const finished = events.some(e => e.type === 'step_finish' && ['stop', 'end_turn'].includes(e.part?.reason));
    const error = events.some(e => e.type === 'error' || e.part?.state?.status === 'error');
    return { read, replyMatches: reply.includes(marker), finished, error };
}

function summarize(cases, required) {
    if (cases.some(c => c.status === 'FAIL')) return 'FAIL';
    if (required.some(id => !cases.some(c => c.id === id && c.status === 'PASS')) || cases.some(c => c.status === 'BLOCKED')) return 'BLOCKED';
    return 'PASS';
}

function junit(report) {
    const xml = s => String(s ?? '').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
    const fail = report.cases.filter(c => c.status === 'FAIL').length;
    const skipped = report.cases.filter(c => !['PASS', 'FAIL'].includes(c.status)).length;
    return `<?xml version="1.0" encoding="utf-8"?>\n<testsuites><testsuite name="LoKiEnte live toolchain" tests="${report.cases.length}" failures="${fail}" skipped="${skipped}">` +
        report.cases.map(c => `<testcase classname="${xml(c.component)}" name="${xml(c.id)}">` +
            (c.status === 'FAIL' ? `<failure message="${xml(c.evidence)}"/>` : c.status !== 'PASS' ? `<skipped message="${xml(c.evidence)}"/>` : '') + '</testcase>').join('') + '</testsuite></testsuites>\n';
}

async function atomic(file, text, { io = fs, timeoutMs = 5000, retryDelayMs = 25 } = {}) {
    await io.mkdir(path.dirname(file), { recursive: true });
    const temporary = `${file}.${crypto.randomUUID()}.tmp`;
    let written = false, published = false, retries = 0;
    try {
        await io.writeFile(temporary, text, 'utf8'); written = true;
        const started = Date.now();
        for (;;) {
            try { await io.rename(temporary, file); published = true; return { retries }; }
            catch (error) {
                const remaining = timeoutMs - (Date.now() - started);
                if (!['EPERM', 'EACCES', 'EBUSY'].includes(error.code) || remaining <= 0) {
                    error.temporaryFile = temporary; error.reportDestination = file; error.retries = retries;
                    error.message += ` Last complete destination was preserved. Pending snapshot: ${temporary}`;
                    throw error;
                }
                await new Promise(resolve => setTimeout(resolve, Math.min(remaining, 250, retryDelayMs * 2 ** Math.min(retries++, 4))));
            }
        }
    } finally {
        // A complete snapshot is evidence when replacement remains blocked.
        // Never delete/truncate the current destination as a rename fallback.
        if (published || !written) await io.unlink(temporary).catch(() => {});
    }
}

async function checkToolchain({ vscode, root, logger, env = process.env, reportPath, project, runId, interactive = true, diagnostics = () => ({}), signal: outerSignal, persistenceOptions }) {
    runId ||= crypto.randomUUID().replaceAll('-', '');
    const directory = path.join(root, 'diagnostics', 'toolchain', runId);
    reportPath ||= path.join(directory, 'acceptance.json');
    project ||= path.join(directory, 'project');
    await fs.mkdir(project, { recursive: true });
    const prelaunch = await fs.readFile(reportPath, 'utf8').then(JSON.parse).catch(error => { if (error.code === 'ENOENT') return null; throw error; });
    const required = ['vscode-host', 'workspace-trust', 'managed-helper', 'acceptance-project-git', 'kilo-discovery', 'production-configuration', 'kilo-activation', 'installed-runtime', 'dependencies', 'model-catalog', 'kilo-webview-request', 'kilo-visible-response'];
    const report = { schema: 1, kind: 'live-toolchain-acceptance', runId, status: 'RUNNING', startedAtUtc: new Date().toISOString(),
        executionMode: 'native-windows-applications', requirements: { docker: false, hyperV: false },
        versions: { vscode: vscode.version, node: process.versions.node, electron: process.versions.electron || null }, cases: [], progress: [], nativeCommands: [], reportPath };
    if (prelaunch?.runId === runId) { if (prelaunch.launch) report.launch = prelaunch.launch; if (prelaunch.workspaceTrust) report.workspaceTrust = prelaunch.workspaceTrust; if (prelaunch.projectGit) report.projectPreparation = prelaunch.projectGit; }
    const secrets = Object.entries(env).filter(([name]) => /token|key|password/i.test(name)).map(([, value]) => value);
    const controller = new AbortController(), signal = controller.signal;
    const abort = () => controller.abort(outerSignal.reason);
    outerSignal?.addEventListener('abort', abort, { once: true }); if (outerSignal?.aborted) abort();
    const deadline = Date.parse(env.LOKIENTE_TOOLCHAIN_DEADLINE_UTC || '');
    const deadlineTimer = Number.isFinite(deadline) ? setTimeout(() => controller.abort(new Error('The overall acceptance deadline expired.')), Math.max(0, deadline - Date.now())) : null;
    deadlineTimer?.unref?.();
    const cancelPoll = setInterval(() => {
        void fs.readFile(path.join(directory, 'cancellation.json'), 'utf8').then(JSON.parse).then(value => {
            if (value.runId === runId) controller.abort(new Error(value.reason || 'Acceptance cancelled by its native runner.'));
        }).catch(error => { if (error.code !== 'ENOENT') controller.abort(new Error('Acceptance cancellation state is unreadable.')); });
    }, 500); cancelPoll.unref?.();
    const write = async (file, text) => {
        try {
            const result = await atomic(file, text, persistenceOptions);
            if (result.retries) logger.info('LoKiEnte', `Report replacement recovered after ${result.retries} sharing/permission retries: ${file}`);
        } catch (error) { error.acceptancePersistence = true; error.reportDestination ||= file; throw error; }
    };
    let saving = Promise.resolve();
    const save = () => {
        const pending = saving.then(async () => {
            await write(reportPath.replace(/\.json$/i, '') + '.junit.xml', junit(report));
            await write(reportPath, JSON.stringify(report, null, 2));
        });
        saving = pending.catch(() => {}); return pending;
    };
    const native = async (file, args, options) => {
        const start = Date.now(); let result, failure;
        try { result = await runNative(file, args, { ...options, signal }); return result; }
        catch (error) { failure = error; result = error.nativeResult; throw error; }
        finally {
            const streams = {};
            for (const name of ['stdout', 'stderr']) {
                const value = redact(result?.[name] || '', secrets);
                streams[name] = { characters: value.length, text: value.slice(0, 262144), truncated: value.length > 262144 };
                if (streams[name].truncated) {
                    const fullLog = path.join(directory, `command-${report.nativeCommands.length}-${name}.log`);
                    await write(fullLog, value); streams[name].fullLog = fullLog;
                }
            }
            report.nativeCommands.push({ utc: new Date().toISOString(), file, args: args.map(value => redact(value, secrets)), cwd: options?.cwd,
                timeoutMs: options?.timeoutMs, durationMs: Date.now() - start, exitCode: result?.code ?? null, error: failure ? redact(failure.message, secrets) : null, streams });
            await save();
        }
    };
    const progress = (id, component, status, evidence = '', metadata = {}) => {
        report.progress.push({ sequence: report.progress.length + 1, utc: new Date().toISOString(), id, component, status, evidence: redact(evidence, secrets), ...metadata });
    };
    const record = async (id, component, status, evidence, metadata = {}) => {
        const entry = { id, component, status, evidence: redact(evidence, secrets), ...metadata };
        report.cases.push(entry); logger[status === 'FAIL' ? 'error' : status === 'BLOCKED' ? 'warn' : 'info'](component, `${status}: ${id}: ${entry.evidence}`);
        progress(id, component, status, entry.evidence, metadata);
        await save(); return entry;
    };
    const check = async (id, component, action) => {
        const started = Date.now();
        logger.info(component, `START: ${id}`);
        progress(id, component, 'RUNNING'); await save();
        let status = 'PASS', evidence;
        try { evidence = await withCancellation(action, signal); }
        catch (e) { if (e.acceptancePersistence) throw e; status = e.blocked ? 'BLOCKED' : 'FAIL'; evidence = e.message; }
        // A report-write failure is not an activation/trust/model failure.
        return await record(id, component, status, evidence, { durationMs: Date.now() - started });
    };
    const blocked = message => Object.assign(new Error(message), { blocked: true });
    try {
    try {
        const host = await record('vscode-host', 'VS Code', vscode.env.appHost === 'desktop' && !!process.versions.electron ? 'PASS' : 'BLOCKED',
            'Requires the real desktop VS Code Extension Host, not a simulated API.', { appHost: vscode.env.appHost });
        if (host.status !== 'PASS') throw blocked('This test must run in the actual desktop Extension Host.');
        report.waitingFor = 'workspace-trust'; await save();
        const trust = await check('workspace-trust', 'VS Code', async () => {
            await waitForWorkspaceTrust(vscode, logger, 600000, signal);
            return 'The test workspace is trusted by a user decision in VS Code.';
        });
        delete report.waitingFor; await save();
        if (trust.status !== 'PASS') throw blocked('Workspace Trust is required before Kilo can run. Review trust in the test window and rerun acceptance.');
        const config = JSON.parse(env.KILO_CONFIG_CONTENT || '{}');
        const chain = JSON.parse(await fs.readFile(path.join(root, 'toolchain.json'), 'utf8'));
        const preparationPath = path.join(directory, 'project-preparation.json');
        report.projectPreparation = await fs.readFile(preparationPath, 'utf8').then(JSON.parse).catch(error => { if (error.code === 'ENOENT') return null; throw error; });
        const options = config.provider?.lmstudio?.options;
        if (!options?.baseURL || config.enabled_providers?.length !== 1 || config.enabled_providers[0] !== 'lmstudio') throw new Error('A single managed local provider is required.');
        const base = loopback(options.baseURL), models = config.provider.lmstudio.models;
        const aliases = Object.keys(models || {});
        if (!aliases.length || aliases.some(alias => !/^[a-z][a-z0-9-]{0,63}$/.test(alias))) throw new Error('Managed model aliases are missing or invalid.');
        required.push(...aliases.map(alias => `model-roundtrip:${alias}`));
        if (config.indexing?.enabled) required.push('embeddings', 'lancedb');
        report.configurationSha256 = crypto.createHash('sha256').update(JSON.stringify(config)).digest('hex');
        const helper = await check('managed-helper', 'LoKiEnte', async () => {
            for (const file of ['extension.cjs', 'diagnostics.cjs', 'toolchain-check.cjs', 'kilo-startup.cjs', 'acceptance-project.cjs', 'acceptance-lifecycle.cjs', 'acceptance-configuration.cjs']) {
                report.sourceSha256 ||= {}; report.expectedSourceSha256 ||= {};
                report.sourceSha256[file] = crypto.createHash('sha256').update(await fs.readFile(path.join(__dirname, file))).digest('hex');
                report.expectedSourceSha256[file] = crypto.createHash('sha256').update(await fs.readFile(path.join(root, 'app', 'vscode-startup', file))).digest('hex');
                if (report.sourceSha256[file] !== report.expectedSourceSha256[file]) throw new Error(`Running LoKiEnte helper differs from the deployed source package: ${file}. Close managed windows and reprovision.`);
            }
            report.versions.expectedHelper = env.LOKIENTE_STARTUP_VERSION || null;
            return 'Running acceptance/helper modules match the deployed package byte for byte (SHA-256).';
        });
        if (helper.status !== 'PASS') throw blocked('The current helper code was not verified; no Kilo/model acceptance was started.');
        const prepared = await check('acceptance-project-git', 'Git', async () => {
            const evidence = await prepareAcceptanceProject({ root, runId, ownerRunId: env.LOKIENTE_TOOLCHAIN_PROJECT_OWNER || runId, git: chain.gitExecutable, env, run: native });
            if (path.resolve(evidence.project).toLowerCase() !== path.resolve(project).toLowerCase()) throw new Error('Unexpected acceptance workspace.');
            report.projectGit = evidence;
            return `Generated Git workspace has a verified initial commit: ${evidence.head}`;
        });
        if (prepared.status !== 'PASS') throw blocked('The generated Git test workspace is unavailable. No Kilo/model check was started.');
        let kilo;
        report.waitingFor = 'kilo-discovery'; await save();
        const discovery = await check('kilo-discovery', 'Kilo Code', async () => {
            const started = Date.now();
            report.kiloDiscovery = { installed: await installedKilo(root), visibleBefore: (vscode.extensions.all || []).map(e => e.id) };
            try { kilo = await waitForKilo({ vscode, root, logger, isDisposed: () => signal.aborted }); }
            catch (error) { report.kiloDiscovery.errorCode = error.code; throw Object.assign(error, { blocked: true }); }
            finally { report.kiloDiscovery.durationMs = Date.now() - started; report.kiloDiscovery.visibleAfter = (vscode.extensions.all || []).map(e => e.id); }
            if (!kilo) throw blocked('Kilo discovery ended without an extension.');
            return 'The installed Kilo extension was discovered in the real running host before activation.';
        });
        delete report.waitingFor; await save();
        if (discovery.status !== 'PASS') throw blocked('Kilo was not discovered; dependent checks were not executed. See kiloDiscovery and Extension Host logs.');
        const configuration = await check('production-configuration', 'VS Code -> LoKiEnte', async () => {
            report.productionConfiguration = {};
            try { Object.assign(report.productionConfiguration, await verifyAcceptanceConfiguration({ vscode, root, runId, env, kilo, evidence: report.productionConfiguration })); }
            catch (error) { report.productionConfiguration.status = 'FAIL'; throw error; }
            return 'The actual work profile and installed extension directory are in use. Settings values, source/configuration hashes and effective user/workspace scopes match the shared desktop launch baseline.';
        });
        if (configuration.status !== 'PASS') throw blocked('Production configuration parity was not established. No model acceptance was claimed.');
        const activation = await check('kilo-activation', 'Kilo Code', async () => {
            await withDeadline(() => kilo.activate(), 90000, 'Kilo activation exceeded 90 seconds.', signal);
            if (signal.aborted) throw cancellationError(signal);
            if (!kilo.isActive) throw new Error('Kilo did not become active.');
            report.versions.kilo = kilo.packageJSON.version;
            for (const id of kilo.packageJSON.extensionDependencies || []) {
                if (signal.aborted) throw cancellationError(signal);
                const dependency = vscode.extensions.getExtension(id);
                if (!dependency) throw new Error(`Required extension is missing: ${id}`);
                await withDeadline(() => dependency.activate(), 90000, `Extension dependency activation timed out: ${id}`, signal);
                if (!dependency.isActive) throw new Error(`Required extension did not activate: ${id}`);
            }
            return 'The installed Kilo extension and its declared extension dependencies activated in the real host.';
        });
        if (activation.status !== 'PASS') throw blocked('Kilo activation failed; dependent live checks were not executed.');
        const binary = path.join(kilo.extensionPath, 'bin', process.platform === 'win32' ? 'kilo.exe' : 'kilo');
        const runtime = await check('installed-runtime', 'Kilo Code', async () => {
            if (path.resolve(binary).toLowerCase() !== path.resolve(env.LOKIENTE_ET_KILO || '').toLowerCase()) throw new Error('The tested CLI is not the runtime bundled with this Kilo extension.');
            const bytes = await fs.readFile(binary); report.runtimeSha256 = crypto.createHash('sha256').update(bytes).digest('hex');
            const result = await native(binary, ['--version'], { cwd: project, env, timeoutMs: 30000 });
            if (result.code !== 0 || !/\d+\.\d+\.\d+/.test(result.stdout)) throw new Error('Embedded Kilo version check failed.');
            report.versions.embeddedKilo = result.stdout.trim(); return 'Installed embedded runtime is executable; its SHA-256 is recorded.';
        });
        if (runtime.status !== 'PASS') throw blocked('The installed Kilo runtime is unavailable; dependent checks were not executed.');
        const dependencies = await check('dependencies', 'LoKiEnte -> Kilo Code', async () => {
            const file = path.join(directory, 'dependencies.json');
            let result;
            try { result = await native(chain.powerShellExecutable, ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', path.join(root, 'app', 'Test-Toolchain.ps1'),
                '-InstallRoot', root, '-DependenciesOnly', '-WorkingDirectory', project, '-ResultPath', file], { cwd: project, env, timeoutMs: 300000 }); }
            finally {
                const text = await fs.readFile(file, 'utf8').catch(error => { if (error.code === 'ENOENT') return null; throw error; });
                if (text) report.dependencies = JSON.parse(text);
            }
            const dependency = report.dependencies;
            if (!dependency) throw new Error('The installed dependency runner produced no report.');
            if (result.code !== 0 || dependency.status !== 'PASS' || dependency.cases.length < 10 || dependency.cases.some(c => c.status !== 'PASS')) {
                const failures = dependency.cases.filter(c => c.status !== 'PASS').map(c => `${c.id}: ${c.evidence}`).join('; ');
                throw new Error(`Installed desktop/Git/CLI/config/tool/search checks failed: ${failures || `process exit ${result.code}`}. See dependencies.json.`);
            }
            return 'Standalone and embedded Kilo passed effective configuration, tool-import and actual file-search checks.';
        });
        if (dependencies.status !== 'PASS') throw blocked('Installed toolchain dependencies failed; dependent inference checks were not executed.');
        const headers = {};
        const ref = /^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/.exec(options.apiKey || '');
        const token = ref ? env[ref[1]] : options.apiKey;
        if (token) headers.authorization = `Bearer ${token}`;
        await check('model-catalog', 'Kilo Code -> LoKiEnte', async () => {
            const catalog = await readJsonResponse(new URL('models', base.href.replace(/\/?$/, '/')).href, headers);
            for (const model of Object.values(models)) if (!catalog.data?.some(item => item.id === model.id)) throw new Error(`Configured model is missing from the live API: ${model.id}`);
            return 'All configured route IDs are present in the live local model API.';
        });
        for (const alias of aliases) {
            const id = `model-roundtrip:${alias}`;
            await check(id, 'Kilo Code -> LoKiEnte -> LM Studio', async () => {
                const marker = `LOKIENTE_ACCEPTANCE_${crypto.randomBytes(16).toString('hex')}`;
                const file = path.join(project, `probe-${alias}.txt`); await fs.writeFile(file, marker + '\n', 'utf8');
                // The marker is NOT in the prompt: a real completed Kilo read
                // and the model's subsequent final response must both prove it.
                const prompt = `Explanation-only question: what exact string is in ${file}? Use your read tool to read that file and answer only with its contents. Do not edit files, execute commands or start a development workflow.`;
                const result = await native(binary, ['run', '--format', 'json', '--agent', 'shadow-chat', '--model', `lmstudio/${alias}`, '--title', `LoKiEnte acceptance ${runId}`, prompt], { cwd: project, env, timeoutMs: 300000 });
                if (result.code !== 0) throw new Error(`Kilo model run failed (exit ${result.code}). Read the LoKiEnte output for Kilo/runtime errors.`);
                const evidence = inspectKiloEvents(result.stdout, marker, file);
                if (!evidence.read || !evidence.replyMatches || !evidence.finished || evidence.error) throw new Error('No complete real read-tool -> model-response round trip was observed.');
                return `Real embedded Kilo, read tool and final LM Studio response passed for ${alias}; no scripted responses were supplied.`;
            });
        }
        if (config.indexing?.enabled) {
            await check('lancedb', 'Kilo indexing -> LanceDB', async () => {
                const module = env.KILO_LANCEDB_PATH;
                const expected = path.join(root, 'tooling', 'lancedb', 'node_modules', '@lancedb', 'lancedb', 'dist', 'index.js');
                if (!module || path.resolve(module).toLowerCase() !== path.resolve(expected).toLowerCase()) throw new Error('The installed local LanceDB dependency is not configured.');
                const script = `const fs=require('node:fs/promises');(async()=>{const db=await require(process.argv[1]).connect(process.argv[2]);const t=await db.createTable('acceptance',[{id:'probe',vector:Array.from({length:768},(_,i)=>i===0?1:0)}]);const r=await t.search(Array.from({length:768},(_,i)=>i===0?1:0)).limit(1).toArray();if(r[0]?.id!=='probe')throw Error('Vector search failed');await db.dropTable('acceptance');console.log('LANCEDB_PASS')})().catch(()=>{process.exitCode=1})`;
                const result = await native(chain.nodeExecutable, ['-e', script, module, path.join(directory, 'lancedb-probe')], { cwd: project, env, timeoutMs: 60000 });
                if (result.code !== 0 || !result.stdout.includes('LANCEDB_PASS')) throw new Error('Real LanceDB native import, table write and vector search failed.');
                return 'Installed LanceDB native dependency passed actual local table write and vector search. Full repository indexing is a separate workload.';
            });
            await check('embeddings', 'Kilo indexing -> LM Studio', async () => {
                const index = config.indexing;
                const endpoint = loopback(index['openai-compatible'].baseUrl);
                const response = await fetch(new URL('embeddings', endpoint.href.replace(/\/?$/, '/')), { method: 'POST', headers: { ...headers, 'content-type': 'application/json' },
                    body: JSON.stringify({ model: index.model, input: 'LoKiEnte acceptance', dimensions: 768 }), signal: AbortSignal.timeout(60000), redirect: 'error' });
                const value = await response.json();
                if (!response.ok || !Array.isArray(value.data?.[0]?.embedding) || value.data[0].embedding.length !== 768 || !value.data[0].embedding.every(Number.isFinite)) throw new Error('Real fixed-size embedding inference failed.');
                return 'Actual embedding inference returned 768 finite values.';
            });
        } else await record('embeddings', 'Kilo indexing', 'NOT_APPLICABLE', 'Indexing is disabled in the prepared configuration.');
        const marker = `LOKIENTE_ACCEPTANCE_${crypto.randomBytes(16).toString('hex')}`;
        const hash = crypto.createHash('sha256').update(marker).digest('hex');
        const started = Date.now();
        const webview = await check('kilo-webview-request', 'VS Code -> Kilo webview -> LM Studio', async () => {
            const commands = await vscode.commands.getCommands(true);
            if (!commands.includes('kilo-code.new.terminalExplainCommand')) throw blocked('This Kilo version does not expose the tested explanation command.');
            // This explains supplied text. It never creates or executes a terminal command.
            await withDeadline(() => vscode.commands.executeCommand('kilo-code.new.terminalExplainCommand', { selection: `printf '${marker}'\n# Include this exact literal marker in the explanation.` }), 90000, 'Kilo webview did not become ready.', signal);
            if (signal.aborted) throw cancellationError(signal);
            const pool = await fs.readFile(path.join(root, 'runtime', 'model-pool.json'), 'utf8').then(JSON.parse).catch(e => { if (e.code === 'ENOENT') return null; throw e; });
            if (!pool) return 'The real Kilo webview accepted the explanation action. Single-mode response delivery requires the following visible check.';
            let completion, failure;
            const tail = new LogTail(path.join(root, 'runtime', 'router-events.jsonl'), line => {
                let event; try { event = JSON.parse(line); } catch { return; }
                if (event.probeHash !== hash) return;
                if (event.event === 'request_failed') failure = event.code;
                if (event.event === 'request_completed' && event.probeReplyMatched === true) completion = event;
            }, { replayBytes: 1024 * 1024 });
            while (Date.now() - started < 300000 && !signal.aborted) {
                await tail.read();
                if (failure) throw new Error(`The real Kilo webview request failed: ${failure}`);
                if (completion) return 'A nonce-correlated real webview request reached LM Studio and completed with the expected literal response.';
                await new Promise(resolve => setTimeout(resolve, 500));
            }
            if (signal.aborted) throw cancellationError(signal);
            throw new Error('No completed nonce-correlated Kilo webview -> router -> LM Studio exchange was observed.');
        });
        if (webview.status !== 'PASS') await record('kilo-visible-response', 'Kilo Code UI', 'BLOCKED', 'The webview request failed; no visible response can be accepted.');
        else if (!interactive) await record('kilo-visible-response', 'Kilo Code UI', 'BLOCKED', 'Visible webview rendering has not been observed. Noninteractive checks cannot claim this evidence.');
        else {
            report.waitingFor = 'kilo-visible-response confirmation';
            progress('kilo-visible-response', 'Kilo Code UI', 'RUNNING'); await save();
            let answer;
            try { answer = await withCancellation(() => vscode.window.showInformationMessage(`LoKiEnte acceptance: is the completed Kilo explanation containing ${marker} visible in this test window?`,
                { modal: true, detail: 'Confirm the actual Kilo chat response, not the Output log or this question. A missing/unconfirmed response prevents full acceptance.' }, 'Response is visible', 'Response is missing', 'Skip visual check'), signal); }
            finally { delete report.waitingFor; }
            await record('kilo-visible-response', 'Kilo Code UI', answer === 'Response is visible' ? 'PASS' : answer === 'Response is missing' ? 'FAIL' : 'BLOCKED',
                answer === 'Response is visible' ? 'User observed the nonce-bearing response in the real Kilo webview.' : 'The real Kilo response was not confirmed visible.', { evidenceKind: 'manual-visual-observation' });
        }
    } catch (e) { if (e.acceptancePersistence) throw e; await record('acceptance-prerequisite', 'LoKiEnte', e.blocked ? 'BLOCKED' : 'FAIL', e.message); }
    for (const id of required) if (!report.cases.some(c => c.id === id)) await record(id, 'LoKiEnte', 'BLOCKED', 'Not executed because a prerequisite was unavailable.');
    if (signal.aborted) await record('acceptance-cancelled', 'LoKiEnte', 'BLOCKED', cancellationError(signal).message);
    report.status = summarize(report.cases, required); report.required = required; report.finishedAtUtc = new Date().toISOString();
    report.diagnostics = diagnostics();
    await write(path.join(root, 'diagnostics', 'toolchain', 'latest.json'), JSON.stringify(report, null, 2));
    await write(path.join(root, 'diagnostics', 'toolchain', 'latest.junit.xml'), junit(report));
    // The coordinator observes terminal status only after final artifact writes.
    await save();
    logger[report.status === 'PASS' ? 'info' : 'error']('LoKiEnte', `Toolchain acceptance: ${report.status}. Report: ${reportPath}`);
    return report;
    } catch (error) {
        controller.abort(error);
        await saving;
        const original = reportPath, failurePath = reportPath.replace(/\.json$/i, '.failure.json');
        report.status = 'FAIL'; report.finishedAtUtc = new Date().toISOString(); report.required = required;
        report.failureStage = report.waitingFor || null; delete report.waitingFor;
        if (error.acceptancePersistence) report.persistenceFailure = { code: error.code, syscall: error.syscall, destination: error.reportDestination,
            pendingSnapshot: error.temporaryFile, retries: error.retries, primaryReportPath: original };
        const reason = error.acceptancePersistence ? 'acceptance report persistence failed' : 'an unexpected acceptance error occurred';
        report.cases.push({ id: error.acceptancePersistence ? 'report-persistence' : 'acceptance-internal', component: 'LoKiEnte', status: 'FAIL', evidence: redact(error.message, secrets) });
        for (const id of required) if (!report.cases.some(c => c.id === id)) report.cases.push({ id, component: 'LoKiEnte', status: 'BLOCKED', evidence: `Not completed because ${reason}.` });
        report.reportPath = failurePath;
        await write(failurePath.replace(/\.json$/i, '.junit.xml'), junit(report));
        await write(failurePath, JSON.stringify(report, null, 2));
        logger.error('LoKiEnte', `Acceptance stopped because ${reason}. Failure report: ${failurePath}. ${redact(error.message, secrets)}`);
        return report;
    } finally { clearInterval(cancelPoll); clearTimeout(deadlineTimer); outerSignal?.removeEventListener('abort', abort); }
}

module.exports = { runNative, inspectKiloEvents, summarize, junit, atomic, checkToolchain, withDeadline, waitForWorkspaceTrust };
