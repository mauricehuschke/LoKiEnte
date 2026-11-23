const http = require('node:http');
const { renderPage } = require('./page.cjs');
const sampleTickets = require('../fixtures/tickets.json');

function createServer(tickets = sampleTickets) {
    return http.createServer((request, response) => {
        if (request.method !== 'GET') {
            response.writeHead(405, { Allow: 'GET' }).end();
        } else if (request.url === '/') {
            response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end(renderPage(tickets));
        } else if (request.url === '/health') {
            response.writeHead(200, { 'Content-Type': 'application/json' }).end('{"ok":true}');
        } else {
            response.writeHead(404).end();
        }
    });
}

if (require.main === module) {
    createServer().listen(4318, '127.0.0.1', () => console.log('Open http://127.0.0.1:4318/'));
}
module.exports = { createServer };
