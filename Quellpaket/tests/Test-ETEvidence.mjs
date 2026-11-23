import assert from 'node:assert/strict';
import {test} from 'node:test';
import probe from '../security-probe/et.test.cjs';
const vmId='4ebcb863-2698-4362-8fb7-b5551ddc3b97';
const guest={id:'{'+vmId+'}',boot:'2026-01-02T10:00:00Z'};
const challenge={schema:1,vmId,markerPath:'D:\\Private\\lokiente-et-'+vmId+'.probe',createdUtc:'2026-01-02T10:01:00Z'};
test('only fresh challenges for the current guest and synthetic marker are accepted',()=>{
    probe.verifyChallenge(challenge,guest);
    for(const bad of [{vmId:'wrong'},{createdUtc:'2025-12-31T10:00:00Z'},{markerPath:'D:\\Private\\secret.txt'},{schema:2}]){
        assert.throws(()=>probe.verifyChallenge({...challenge,...bad},guest));
    }
});
test('a model smoke test rejects remote providers and endpoints before a request',()=>{
    const cfg={model:'lmstudio/coder',provider:{lmstudio:{models:{coder:{id:'fixture'}},options:{baseURL:'http://127.0.0.1:1235/v1'}}}};
    assert.equal(typeof probe.modelRequest(cfg),'function');
    cfg.provider.lmstudio.options.baseURL='https://example.invalid/v1';
    assert.throws(()=>probe.modelRequest(cfg),/loopback/);
});
