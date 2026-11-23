'use strict';
const https = require('node:https');
const tls = require('node:tls');

const url = 'https://www.lokiente.dev/fit-test.txt';
const canonical = 'https://lokiente.dev/fit-test.txt';
const marker = 'Success';

// Fixed public fixture only. Never send project data, credentials or model arguments.
function get(url) {
    return new Promise(resolve => {
        let timer;
        const finish = value => { clearTimeout(timer); resolve(value); };
        const options = {agent:false, headers:{Accept:'text/plain'}};
        if (typeof tls.getCACertificates === 'function') {
            options.ca = [...tls.getCACertificates('default'), ...tls.getCACertificates('system')];
        }
        const req = https.get(url, options, res => {
            const status = res.statusCode;
            if (status !== 200) {
                const location = res.headers.location;
                res.destroy();
                finish({status, location});
                return;
            }
            const chunks = [];
            let size = 0;
            res.on('error', () => finish({status, error:'Incomplete response'}));
            res.on('data', chunk => {
                size += chunk.length;
                if (size > 256) {
                    finish({status, error:'Response exceeds the marker size limit'});
                    res.destroy();
                } else chunks.push(chunk);
            });
            res.on('end', () => finish({status, body:Buffer.concat(chunks).toString('utf8')}));
        });
        req.on('error', () => finish({error:'HTTPS request failed'}));
        timer = setTimeout(() => { finish({error:'HTTPS request timed out'}); req.destroy(); }, 8000);
    });
}

async function checkReference(fetchFixed=get) {
    const hops = [];
    let result = await fetchFixed(url);
    hops.push({url, status:result.status ?? null});
    if ([301,302,303,307,308].includes(result.status) && result.location === canonical) {
        result = await fetchFixed(canonical);
        hops.push({url:canonical, status:result.status ?? null});
    }
    const matched = result.status === 200 && [marker, marker+'\n', marker+'\r\n'].includes(result.body);
    const detail = matched ? 'The public reference returned HTTP 200 and the expected marker.' :
        result.error || (result.status === 200 ? 'The public response did not match the expected marker.' :
            'The reference did not return the marker (HTTP '+(result.status ?? 'unknown')+').');
    return {status:matched?'PASS':'UNVERIFIED', detail, observed:{actor:'LoKiEnte reference check',hops,markerMatched:matched,receivedMarker:matched?marker:null}};
}
module.exports = {url,marker,checkReference};
