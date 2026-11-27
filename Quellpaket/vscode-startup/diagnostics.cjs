'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { StringDecoder } = require('node:string_decoder');

function redact(value, secrets = []) {
    let text = String(value ?? '');
    for (const secret of secrets.filter(s => typeof s === 'string' && s.length > 3)) text = text.split(secret).join('[REDACTED]');
    return text.replace(/(Bearer\s+|Basic\s+)[A-Za-z0-9+/_=.:-]+/gi, '$1[REDACTED]')
        .replace(/((?:api[_-]?key|password|authorization|auth_token|access_token|refresh_token)\s*["']?\s*[:=]\s*["']?)[^\s"',;}]+/gi, '$1[REDACTED]')
        .replace(/([?&](?:token|key|password|auth_token)=)[^&\s]+/gi, '$1[REDACTED]');
}

function createLogger(output, secrets = []) {
    const listeners = new Set();
    const write = (level, component, message) => {
        const event = { utc: new Date().toISOString(), level, component, message: redact(message, secrets).slice(0, 16384) };
        const line = `[${event.component}] ${event.message}`;
        const method = level === 'ERROR' ? 'error' : level === 'WARN' ? 'warn' : 'info';
        if (typeof output[method] === 'function') output[method](line); else output.appendLine(`${event.utc} [${level}] ${line}`);
        if (level === 'ERROR') output.show(true);
        for (const listener of listeners) { try { listener(event); } catch {} }
        return event;
    };
    return {
        info: (c, m) => write('INFO', c, m), warn: (c, m) => write('WARN', c, m), error: (c, m) => write('ERROR', c, m),
        subscribe(fn) { listeners.add(fn); return { dispose: () => listeners.delete(fn) }; },
    };
}

class LogTail {
    constructor(file, consume, { replayBytes = 65536, maxReadBytes = 262144 } = {}) {
        Object.assign(this, { file, consume, replayBytes, maxReadBytes });
        this.offset = null; this.pending = ''; this.decoder = new StringDecoder('utf8'); this.identity = null;
    }
    async read() {
        let handle;
        try {
            handle = await fs.open(this.file, 'r');
            const stat = await handle.stat();
            const identity = `${stat.dev}:${stat.ino}:${stat.birthtimeMs}`;
            if (this.identity !== identity || this.offset === null || stat.size < this.offset) {
                this.identity = identity; this.offset = Math.max(0, stat.size - this.replayBytes);
                this.pending = ''; this.decoder = new StringDecoder('utf8');
                if (this.offset) this.pending = null; // Discard the first partial line of a bounded replay.
            }
            let budget = this.maxReadBytes;
            while (this.offset < stat.size && budget > 0) {
                const buffer = Buffer.alloc(Math.min(32768, stat.size - this.offset, budget));
                const { bytesRead } = await handle.read(buffer, 0, buffer.length, this.offset);
                if (!bytesRead) break;
                this.offset += bytesRead; budget -= bytesRead;
                let decoded = this.decoder.write(buffer.subarray(0, bytesRead));
                if (this.pending === null) {
                    const end = decoded.indexOf('\n');
                    if (end < 0) continue;
                    this.pending = ''; decoded = decoded.slice(end + 1);
                }
                this.pending += decoded;
                let end;
                while ((end = this.pending.indexOf('\n')) >= 0) {
                    const line = this.pending.slice(0, end).replace(/\r$/, '');
                    this.pending = this.pending.slice(end + 1);
                    this.consume(line);
                }
                if (this.pending.length > 65536) this.pending = null;
            }
        } catch (e) { if (e.code !== 'ENOENT') throw e; }
        finally { await handle?.close(); }
    }
}

async function logFiles(root, depth = 4, limit = 150) {
    const result = [];
    async function walk(dir, remaining) {
        if (result.length >= limit) return;
        let entries; try { entries = await fs.readdir(dir, { withFileTypes: true }); } catch (e) { if (e.code === 'ENOENT') return; throw e; }
        entries.sort((a, b) => b.name.localeCompare(a.name));
        for (const entry of entries) {
            if (entry.isSymbolicLink() || result.length >= limit) continue;
            const file = path.join(dir, entry.name);
            if (entry.isDirectory() && remaining) await walk(file, remaining - 1);
            else if (entry.isFile() && /\.(log|jsonl)$/i.test(entry.name) && !/^\d*-?LoKiEnte\.(log|jsonl)$/i.test(entry.name)) result.push(file);
        }
    }
    await walk(root, depth); return result;
}

function consumeLine(logger, component, line) {
    if (!line.trim()) return;
    if (line.startsWith('{')) {
        let event; try { event = JSON.parse(line); } catch { return; }
        if (component === 'Router') {
            if (typeof event.event !== 'string') return;
            const level = /fail|reject|timeout|timed_out/.test(event.event) ? 'ERROR' : 'INFO';
            const fields = ['event', 'alias', 'code', 'requestId', 'modelId', 'phase', 'elapsedMs', 'status'];
            const text = fields.filter(k => event[k] !== undefined).map(k => `${k}=${event[k]}`).join(' ');
            logger[level === 'ERROR' ? 'error' : 'info'](component, text); return;
        }
        if (event.component && event.level && typeof event.message === 'string') {
            logger[event.level === 'ERROR' ? 'error' : event.level === 'WARN' ? 'warn' : 'info'](event.component, event.message); return;
        }
        if (component === 'Kilo Code' && /^(info|warn|error)$/i.test(event.level || '') && typeof event.message === 'string') {
            logger[event.level.toLowerCase()](component, event.message); return;
        }
        return; // Do not forward prompt/completion JSON from third-party logs.
    }
    const severity = /\[(ERROR|WARN(?:ING)?|INFO|DEBUG|TRACE)\]/i.exec(line);
    if (severity && /DEBUG|TRACE/i.test(severity[1])) return;
    if (component === 'LM Studio' && !severity) return;
    const level = severity && /ERROR/i.test(severity[1]) || /^(?:Error:|Exception:)/i.test(line) ? 'error' :
        severity && /WARN/i.test(severity[1]) ? 'warn' : 'info';
    logger[level](/\[Kilo(?: New)?\]/i.test(line) ? 'Kilo Code' : component, line);
}

function loopback(value) {
    const url = new URL(value);
    if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) || url.username || url.password || url.search || url.hash)
        throw new Error('Diagnostics require an HTTP loopback endpoint without URL credentials.');
    return url;
}

async function readJsonResponse(url, headers, timeout = 3000) {
    const response = await fetch(loopback(url), { headers, redirect: 'error', signal: AbortSignal.timeout(timeout) });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    let size = 0; const chunks = [];
    for await (const chunk of response.body) {
        size += chunk.length;
        if (size > 2 * 1024 * 1024) throw new Error('Diagnostic response exceeded its size limit.');
        chunks.push(chunk);
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function startDiagnostics({ logger, root, dataDirectory, env = process.env, intervalMs = 5000 }) {
    let disposed = false, busy = false;
    const tails = new Map(), states = new Map();
    const changed = (key, state, component, message, error = false) => {
        if (states.get(key) === state) return;
        states.set(key, state); logger[error ? 'error' : 'info'](component, message);
    };
    const poll = async () => {
        if (disposed || busy) return;
        busy = true;
        try {
            const sources = [
                [path.join(dataDirectory, 'logs'), 'VS Code', 5],
                [path.join(root, 'runtime', 'pool-logs'), 'Model controller', 0],
                [path.join(root, 'runtime', 'logs'), 'Model controller', 0],
                [path.join(root, 'runtime', 'launcher-logs'), 'Desktop runner', 0],
                [path.join(root, 'runtime-profile', 'data', 'kilo', 'log'), 'Kilo Code', 1],
            ];
            try {
                let state;
                for (const file of ['model-pool.json', 'runtime-state.json']) {
                    try { state = JSON.parse(await fs.readFile(path.join(root, 'runtime', file), 'utf8')); if (state.LmsPath) break; }
                    catch (e) { if (e.code !== 'ENOENT') throw e; }
                }
                if (state?.LmsPath) sources.push([path.join(path.dirname(path.dirname(state.LmsPath)), 'server-logs'), 'LM Studio', 2]);
            } catch (e) { if (e.code !== 'ENOENT') changed('pool-file', 'invalid', 'LoKiEnte', 'Model pool state is unreadable.', true); }
            const files = [[path.join(root, 'runtime', 'router-events.jsonl'), 'Router'], [path.join(root, 'runtime', 'toolchain-events.jsonl'), 'LoKiEnte']];
            try {
                const failure = JSON.parse(await fs.readFile(path.join(root, 'runtime', 'model-switch-failure.json'), 'utf8'));
                changed('model-failure', JSON.stringify(failure), 'Model controller', JSON.stringify(failure), true);
            } catch (e) { if (e.code !== 'ENOENT') changed('model-failure-read', e.message, 'Model controller', `Cannot read model failure: ${e.message}`, true); }
            for (const [dir, component, depth] of sources) {
                try {
                    const discovered = await logFiles(dir, depth);
                    changed(`source:${dir}`, discovered.length ? 'available' : 'waiting', component, discovered.length ? 'Managed log source is being monitored.' : 'Waiting for managed log files; this source has not produced readable logs yet.');
                    for (const file of discovered) files.push([file, component]);
                }
                catch (e) { changed(dir, e.code, component, `Cannot read managed logs: ${e.code || e.message}`, true); }
            }
            const active = new Set(files.map(([file]) => file));
            for (const file of tails.keys()) if (!active.has(file)) tails.delete(file);
            for (const [file, component] of files) {
                if (!tails.has(file)) tails.set(file, new LogTail(file, line => consumeLine(logger, component, line)));
                try { await tails.get(file).read(); } catch (e) { changed(file, e.code, component, `Log read failed: ${e.code || e.message}`, true); }
            }
            let config;
            try { config = JSON.parse(env.KILO_CONFIG_CONTENT || '{}'); } catch { changed('config', 'invalid', 'LoKiEnte', 'KILO_CONFIG_CONTENT is invalid JSON.', true); return; }
            const options = config.provider?.lmstudio?.options;
            if (!options?.baseURL) { changed('config', 'missing', 'LoKiEnte', 'The managed LM Studio provider is missing.', true); return; }
            const base = loopback(options.baseURL), headers = {};
            const ref = /^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/.exec(options.apiKey || '');
            const token = ref ? env[ref[1]] : options.apiKey;
            if (token) headers.authorization = `Bearer ${token}`;
            try {
                const models = await readJsonResponse(new URL('models', base.href.replace(/\/?$/, '/')).href, headers);
                if (!Array.isArray(models.data)) throw new Error('Invalid /models response.');
                changed('provider', 'ready', 'Kilo Code -> LoKiEnte', 'Managed model endpoint is reachable; its model catalog is readable.');
            } catch (e) { changed('provider', e.message, 'Kilo Code -> LoKiEnte', `Managed model endpoint failed: ${e.message}`, true); }
            const poolPath = path.join(root, 'runtime', 'model-pool.json');
            try {
                const pool = JSON.parse(await fs.readFile(poolPath, 'utf8'));
                const health = await readJsonResponse(new URL('/health', loopback(pool.RouterApiBaseUrl)).href, headers);
                if (health.service !== 'shadow-local-model-router' || health.ready !== true) throw new Error('Router is not ready.');
                changed('router', JSON.stringify(health.currentRequest || 'idle'), 'LoKiEnte -> LM Studio',
                    health.currentRequest ? `${health.currentRequest.phase}: ${health.currentRequest.alias}` : 'Router is ready and idle.');
                const backend = await readJsonResponse(new URL('models', loopback(pool.BackendApiBaseUrl).href.replace(/\/?$/, '/')).href, headers);
                if (!Array.isArray(backend.data)) throw new Error('Invalid LM Studio model catalog.');
                changed('backend', 'ready', 'LM Studio', 'Local API is reachable. Inference is verified only by the acceptance test, not by this health check.');
            } catch (e) { if (e.code !== 'ENOENT') changed('router', e.message, 'LoKiEnte -> LM Studio', `Connection failed: ${e.message}`, true); }
        } catch (e) { changed('monitor', e.message, 'LoKiEnte', `Diagnostics failed: ${e.message}`, true); }
        finally { busy = false; }
    };
    const timer = setInterval(() => void poll(), intervalMs); timer.unref?.();
    const ready = poll();
    return { ready, poll, dispose() { disposed = true; clearInterval(timer); } };
}

module.exports = { redact, createLogger, LogTail, logFiles, consumeLine, loopback, readJsonResponse, startDiagnostics };
