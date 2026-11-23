const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createServer } = require('../src/server.cjs');
const tickets = require('../fixtures/tickets.json');

async function withBoard(records, inspect) {
    const server = createServer(records);
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    try {
        await inspect('http://127.0.0.1:' + server.address().port);
    } finally {
        await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    }
}

test('serves-summary', async () => {
    const internal = { visibility: 'internal', status: 'closed', title: 'Internal case', contact: 'extra-private' };
    await withBoard([...tickets, internal], async base => {
        const response = await fetch(base + '/api/summary');
        assert.equal(response.status, 200);
        assert.match(response.headers.get('content-type'), /application\/json/);
        assert.deepEqual(await response.json(), { open: 2, closed: 1 });
        const page = await fetch(base + '/');
        assert.equal(page.status, 200);
        const html = await page.text();
        assert.match(html, /<dt>Closed<\/dt>\s*<dd>1<\/dd>/);
        assert.ok(!html.includes(internal.title) && !html.includes(internal.contact));
    });
});

test('empty-queue', async () => {
    await withBoard([], async base => {
        const response = await fetch(base + '/api/summary');
        assert.equal(response.status, 200);
        assert.deepEqual(await response.json(), { open: 0, closed: 0 });
    });
});

test('preserves-health', async () => {
    await withBoard([], async base => {
        assert.deepEqual(await (await fetch(base + '/health')).json(), { ok: true });
        assert.equal((await fetch(base + '/missing')).status, 404);
        assert.equal((await fetch(base + '/api/summary', { method: 'POST' })).status, 405);
    });
});
