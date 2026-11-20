import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {createModelRouter} from '../ModelRouter.mjs';

const owner='a'.repeat(24),model=`shadow-${owner}-embedding`;
const vector=Array.from({length:768},(_,i)=>0.01+(i%7)/100);
const encoded=Buffer.alloc(3072);vector.forEach((value,i)=>encoded.writeFloatLE(value,i*4));
function result(body){
  const input=typeof body.input==='string'?[body.input]:body.input;
  return {data:input.map((_,index)=>({index,embedding:body.encoding_format==='float'?vector:encoded.toString('base64')}))};
}
async function fixture(t,{handler,token='',timeout=5000,controller}={}){
  const received=[],logs=[];let switches=0;
  const backend=http.createServer(async(req,res)=>{
    let text='';for await(const part of req)text+=part;
    const body=JSON.parse(text);received.push({path:req.url,body,authorization:req.headers.authorization});
    if(handler){await handler(body,res,req);return;}
    // Reproduce a backend that cannot accept Kilo's optional dimensions field.
    if(body.dimensions!==undefined){res.writeHead(400);res.end(JSON.stringify({error:{message:'Invalid field: dimensions'}}));return;}
    res.setHeader('content-type','application/json');
    res.end(JSON.stringify(req.url==='/v1/embeddings'?result(body):{choices:[{message:{content:'ok'}}]}));
  });
  backend.listen(0,'127.0.0.1');await once(backend,'listening');
  const config={SchemaVersion:2,Status:'Ready',OwnerId:owner,BackendApiBaseUrl:`http://127.0.0.1:${backend.address().port}/v1`,
    Profiles:['coder','review'].map(alias=>({Alias:alias,RouteId:`shadow-${alias}`,InstanceId:`owned-${alias}`,ContextLength:8192,OutputLimit:1024,SmokeTests:{Chat:'Passed',ToolCall:'Passed',ToolResultRoundTrip:'Passed'}}))};
  const router=createModelRouter({config,configDigest:'fixture',token,controlToken:'test-control',requestTimeoutMs:timeout,
    log:event=>logs.push(event),switchModel:async profile=>{switches++;await controller?.();return {Status:'Ready',Alias:profile.Alias,ModelId:profile.InstanceId,ContextLength:profile.ContextLength,Parallel:1};}});
  router.listen(0,'127.0.0.1');await once(router,'listening');
  t.after(async()=>{await Promise.all([router,backend].map(server=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();})));});
  const base=`http://127.0.0.1:${router.address().port}`;
  return {received,logs,base,switches:()=>switches,
    send:(body={model,input:['test'],encoding_format:'base64',dimensions:768},headers={})=>fetch(`${base}/v1/embeddings`,{method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify(body)})};
}

test('Kilo-shaped requests reach fixed-size LM Studio embeddings without dimensions',async t=>{
  const f=await fixture(t);
  const response=await f.send();assert.equal(response.status,200);
  assert.equal((await response.json()).data[0].embedding,encoded.toString('base64'));
  assert.deepEqual(f.received[0].body,{model,input:['test'],encoding_format:'base64'});
  assert.equal(f.switches(),0);
  const floats=await f.send({model,input:['one','two'],dimensions:768,encoding_format:'float'});
  assert.equal(floats.status,200);assert.equal((await floats.json()).data.length,2);
  const single=await f.send({model,input:'one'});assert.equal(single.status,200);
});

test('authentication and browser-origin policy also cover embeddings',async t=>{
  const f=await fixture(t,{token:'synthetic-api-token'});
  assert.equal((await f.send()).status,401);
  assert.equal((await f.send(undefined,{authorization:'Bearer synthetic-api-token',origin:'https://example.invalid'})).status,403);
  assert.equal(f.received.length,0);
  assert.equal((await f.send(undefined,{authorization:'Bearer synthetic-api-token'})).status,200);
  assert.equal(f.received[0].authorization,'Bearer synthetic-api-token');
  assert.deepEqual(f.logs,[]);
});

test('only owned model, exact dimension and supported bounded text requests are accepted',async t=>{
  const f=await fixture(t);
  for(const body of [null,[],{model:'foreign',input:['test']},{model,input:['test'],dimensions:512},
    {model,input:['test'],dimensions:'768'},{model,input:[]},{model,input:[1]},{model,input:['']},
    {model,input:Array(129).fill('x')},{model,input:['test'],encoding_format:'unexpected'},
    {model,input:['test'],baseUrl:'https://example.invalid'}])assert.equal((await f.send(body)).status,400);
  assert.equal(f.received.length,0);
});

for(const [name,change] of [
  ['wrong dimension',r=>{r.data[0].embedding=vector.slice(1);}],
  ['zero vector',r=>{r.data[0].embedding=Array(768).fill(0);}],
  ['non-numeric vector',r=>{r.data[0].embedding=Array(768).fill(null);}],
  ['malformed Base64',r=>{r.data[0].embedding='!'.repeat(4096);}],
  ['duplicate index',r=>{r.data[1].index=0;}],
  ['missing result',r=>{r.data.pop();}],
])test(`rejects ${name} instead of hiding an embedding mismatch`,async t=>{
  const f=await fixture(t,{handler:(body,res)=>{const reply=result(body);change(reply);res.end(JSON.stringify(reply));}});
  assert.equal((await f.send({model,input:['one','two']})).status,502);
});

test('backend authentication errors are preserved without exposing response contents',async t=>{
  const f=await fixture(t,{handler:(_body,res)=>{res.writeHead(401);res.end('private upstream response');}});
  const response=await f.send();assert.equal(response.status,401);
  assert.ok(!(await response.text()).includes('private upstream response'));
  assert.equal(f.received.length,1);assert.equal(f.logs.length,1);
});

test('CPU embeddings proceed while a coding model is loading',async t=>{
  let release,entered;const waiting=new Promise(r=>{release=r;});const started=new Promise(r=>{entered=r;});
  const f=await fixture(t,{controller:async()=>{entered();await waiting;}});
  const chat=fetch(`${f.base}/v1/chat/completions`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({model:'shadow-coder',messages:[{role:'user',content:'test'}]})});
  await started;
  try{assert.equal((await f.send()).status,200);assert.equal(f.switches(),1);}
  finally{release();}
  assert.equal((await chat).status,200);
});

test('active embeddings bound concurrency and prevent a managed shutdown',async t=>{
  let release,entered;const waiting=new Promise(r=>{release=r;});const started=new Promise(r=>{entered=r;});let count=0;
  const f=await fixture(t,{handler:async(body,res)=>{if(++count===2)entered();await waiting;res.end(JSON.stringify(result(body)));}});
  const first=f.send(),second=f.send();await started;
  try{
    const health=await (await fetch(`${f.base}/health`)).json();assert.equal(health.busy,true);assert.equal(health.embeddingRequests,2);
    assert.equal((await f.send()).status,429);
    const stop=await fetch(`${f.base}/admin/shutdown`,{method:'POST',headers:{'x-shadow-control':'test-control'}});assert.equal(stop.status,409);
  }finally{release();}
  assert.equal((await first).status,200);assert.equal((await second).status,200);
});

test('embedding timeout answers the client and releases busy state',async t=>{
  const f=await fixture(t,{timeout:60,handler:()=>{}});
  assert.equal((await f.send()).status,504);
  await new Promise(r=>setTimeout(r,30));
  const health=await (await fetch(`${f.base}/health`)).json();assert.equal(health.embeddingRequests,0);assert.equal(health.busy,false);
});
