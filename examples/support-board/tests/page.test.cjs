const { test } = require('node:test');
const assert = require('node:assert/strict');
const { renderPage } = require('../src/page.cjs');
const tickets = require('../fixtures/tickets.json');

test('shows-team-counts', () => {
    const html = renderPage(tickets);
    assert.match(html, /<dt>Open<\/dt>\s*<dd>2<\/dd>/);
    assert.match(html, /<dt>Closed<\/dt>\s*<dd>1<\/dd>/);
    const empty = renderPage([]);
    assert.match(empty, /<dt>Open<\/dt>\s*<dd>0<\/dd>/);
    assert.match(empty, /<dt>Closed<\/dt>\s*<dd>0<\/dd>/);
});

test('protects-ticket-details', () => {
    const html = renderPage(tickets);
    for (const ticket of tickets) {
        assert.ok(!html.includes(ticket.title));
        assert.ok(!html.includes(ticket.contact));
    }
});
