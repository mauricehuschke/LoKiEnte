const { summarize } = require('./tickets.cjs');

function sendSummary(request, response, tickets) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
        response.writeHead(405, { Allow: 'GET, HEAD' }).end();
        return;
    }

    const body = JSON.stringify(summarize(tickets));
    response.writeHead(200, {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
    });
    response.end(request.method === 'HEAD' ? undefined : body);
}

module.exports = { sendSummary };
