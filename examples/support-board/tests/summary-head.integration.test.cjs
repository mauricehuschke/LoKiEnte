const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const http = require('node:http');
const { createServer } = require('../src/server.cjs');
const sample = require('../fixtures/tickets.json');

async function withApi(tickets, check) {
    const server = createServer(tickets);
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    try {
        const request = (method, path = '/api/summary') => new Promise((resolve, reject) => {
            const req = http.request({ hostname: '127.0.0.1', port: server.address().port, method, path }, res => {
                const chunks = [];
                res.on('data', chunk => chunks.push(chunk));
                res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
                res.on('error', reject);
            });
            req.on('error', reject);
            req.end();
        });
        await check(request);
    } finally {
        await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    }
}

test('head-matches-get', async () => {
    await withApi(sample, async request => {
        const get = await request('GET');
        const head = await request('HEAD');
        assert.equal(head.status, 200);
        assert.equal(head.status, get.status);
        assert.equal(head.headers['content-type'], get.headers['content-type']);
        assert.equal(head.headers['content-length'], String(get.body.length));
        assert.equal(head.headers['content-length'], get.headers['content-length']);
        assert.equal(head.body.length, 0);
    });
});

test('summary-allow', async () => {
    await withApi([], async request => {
        const rejected = await request('POST');
        assert.equal(rejected.status, 405);
        assert.equal(rejected.headers.allow, 'GET, HEAD');
        const health = await request('HEAD', '/health');
        assert.equal(health.status, 405);
        assert.equal(health.headers.allow, 'GET');
    });
});

test('public-representation', async () => {
    const internal = { visibility: 'internal', status: 'open', title: 'Private fixture', contact: 'internal' };
    await withApi([...sample, internal], async request => {
        const get = await request('GET');
        assert.equal(get.status, 200);
        assert.deepEqual(JSON.parse(get.body), { open: 2, closed: 1 });
        const health = await request('GET', '/health');
        assert.equal(health.status, 200);
        assert.deepEqual(JSON.parse(health.body), { ok: true });
    });
});
