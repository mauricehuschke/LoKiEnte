// Local-only, single-slot OpenAI-compatible router. Node >=20, no dependencies.
// Each completed HTTP generation releases the slot so native subagents may use
// another model. Sessions and history remain the responsibility of Kilo.
import http from 'node:http';
import { readFile, writeFile, mkdir, unlink } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { once } from 'node:events';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROUTER_VERSION = '2026.11.27.2';
const BODY_LIMIT = 4 * 1024 * 1024;
const RESPONSE_LIMIT = 16 * 1024 * 1024;
const ALLOWED_FIELDS = new Set(['model','messages','stream','stream_options','max_tokens',
  'max_completion_tokens','temperature','top_p','top_k','min_p','repeat_penalty',
  'presence_penalty','frequency_penalty','seed','tools','tool_choice','parallel_tool_calls',
  'response_format','stop','reasoning_effort','logit_bias','logprobs','top_logprobs','user','n']);

class RouterError extends Error {
  constructor(status, code, message, fatal=false) { super(message); Object.assign(this,{status,code,fatal}); }
}
function equalSecret(left, right) {
  const a=Buffer.from(left||''), b=Buffer.from(right||'');
  return a.length===b.length && timingSafeEqual(a,b);
}
function json(res,status,body) {
  if(res.destroyed||res.writableEnded)return;
  res.writeHead(status,{'content-type':'application/json; charset=utf-8','cache-control':'no-store'});
  res.end(JSON.stringify(body));
}
function errorResponse(res,error) {
  if(res.destroyed||res.writableEnded)return;
  if(res.headersSent){res.destroy();return;}
  json(res,error.status||502,{error:{type:'local_router_error',code:error.code||'local_request_failed',
    message:error instanceof RouterError?error.message:'The local model request failed. Inspect local runtime status.'}});
}
function loopbackUrl(value) {
  const u=new URL(value);
  if(u.protocol!=='http:' || !['127.0.0.1','localhost','[::1]'].includes(u.hostname) || u.username || u.password || u.search || u.hash)
    throw new Error('Only an HTTP loopback backend without credentials is allowed.');
  if(u.pathname.replace(/\/$/,'')!=='/v1')throw new Error('The backend must use its /v1 endpoint.');
  return u;
}
export function validatePool(config) {
  if(config.SchemaVersion!==2||config.Status!=='Ready'||!Array.isArray(config.Profiles)||config.Profiles.length<2)
    throw new Error('A configured multi-model pool is required.');
  const backend=loopbackUrl(config.BackendApiBaseUrl), aliases=new Set(), ids=new Set(), instances=new Set();
  for(const p of config.Profiles){
    if(!p || !/^[a-z][a-z0-9-]{0,40}$/.test(p.Alias)||!/^shadow-[a-z0-9-]+$/.test(p.RouteId)||!p.InstanceId || aliases.has(p.Alias)||ids.has(p.RouteId)||instances.has(p.InstanceId))
      throw new Error('Model aliases and owned instance IDs must be unique and explicit.');
    if(!Number.isInteger(p.ContextLength)||p.ContextLength<8192||!Number.isInteger(p.OutputLimit)||p.OutputLimit<1||p.OutputLimit>=p.ContextLength)
      throw new Error('Verified model context/output limits are missing.');
    const checks=['Chat','ToolCall','ToolResultRoundTrip'];
    const verified=p.SmokeTests&&checks.every(k=>p.SmokeTests[k]==='Passed')&&
      (p.VerificationState===undefined||p.VerificationState==='Verified');
    const deferred=p.VerificationState==='Deferred'&&p.SmokeTests&&
      ['NotRun','NotVerified'].some(status=>checks.every(k=>p.SmokeTests[k]===status));
    if(!verified&&!deferred)throw new Error('Every model must have verified or explicitly deferred smoke tests.');
    aliases.add(p.Alias);ids.add(p.RouteId);instances.add(p.InstanceId);
  }
  return {backend,profiles:new Map(config.Profiles.map(p=>[p.RouteId,p]))};
}
async function readBody(req) {
  if(Number(req.headers['content-length']||0)>BODY_LIMIT)throw new RouterError(413,'body_too_large','Request exceeds the local router body limit.');
  let length=0;const chunks=[];
  for await(const chunk of req){length+=chunk.length;if(length>BODY_LIMIT)throw new RouterError(413,'body_too_large','Request exceeds the local router body limit.');chunks.push(chunk);}
  try{return JSON.parse(Buffer.concat(chunks).toString('utf8'));}
  catch{throw new RouterError(400,'invalid_json','A JSON request object is required.');}
}

export function createModelRouter({config,configDigest,switchModel,token='',controlToken='',requestTimeoutMs=1800000,maxQueued=8,log=()=>{}}) {
  const {backend,profiles}=validatePool(config);
  if(typeof switchModel!=='function')throw new Error('A model switch controller is required.');
  const embeddingId=/^[a-f0-9]{24}$/.test(config.OwnerId||'')?`shadow-${config.OwnerId}-embedding`:null;
  let busy=false,activeAlias=null,shuttingDown=false,fatal=null;
  let currentRequest=null,lastError=null;
  let embeddingRequests=0;
  const queue=[];
  const identity=randomUUID();
  const server=http.createServer((req,res)=>{handle(req,res).catch(e=>errorResponse(res,e));});
  server.headersTimeout=30000;server.requestTimeout=120000;
  async function drain(){
    if(busy)return;busy=true;
    try{while(queue.length){const job=queue.shift();await job();}}
    finally{busy=false;}
  }
  function enqueue(job){queue.push(job);void drain();}
  async function embeddings(req,res){
    if(shuttingDown||fatal)throw new RouterError(503,'router_unavailable','The local router requires attention.');
    const body=await readBody(req);
    if(!body||typeof body!=='object'||Array.isArray(body))throw new RouterError(400,'invalid_embedding_request','An embedding request object is required.');
    if(!embeddingId||body.model!==embeddingId)throw new RouterError(400,'embedding_not_managed','Only the managed local embedding model is exposed.');
    for(const key of Object.keys(body))if(!['model','input','encoding_format','dimensions'].includes(key))
      throw new RouterError(400,'unsupported_embedding_field','The embedding request contains an unsupported field.');
    const inputs=typeof body.input==='string'?[body.input]:body.input;
    if(!Array.isArray(inputs)||!inputs.length||inputs.length>128||inputs.some(value=>typeof value!=='string'||!value.length))
      throw new RouterError(400,'invalid_embedding_input','Provide one to 128 nonempty text inputs.');
    if(body.dimensions!==undefined&&body.dimensions!==768)throw new RouterError(400,'invalid_embedding_dimension','The managed embedding model produces exactly 768 dimensions.');
    if(body.encoding_format!==undefined&&!['base64','float'].includes(body.encoding_format))
      throw new RouterError(400,'invalid_embedding_encoding','Embedding encoding must be base64 or float.');
    // CPU embeddings do not switch the active coding model or wait behind a long
    // generation. Bound concurrency and include this work in shutdown protection.
    if(shuttingDown||fatal)throw new RouterError(503,'router_unavailable','The local router requires attention.');
    if(embeddingRequests>=2)throw new RouterError(429,'embedding_busy','Local embedding capacity is busy. Retry after current requests finish.');
    embeddingRequests++;
    const abort=new AbortController();
    const deadline=setTimeout(()=>{
      const error=new RouterError(504,'embedding_timeout','The local embedding deadline was exceeded.');
      abort.abort(error);errorResponse(res,error);
    },Math.min(requestTimeoutMs,120000));
    const disconnect=()=>{if(!res.writableFinished)abort.abort(new Error('Client disconnected.'));};
    res.once('close',disconnect);req.once('aborted',disconnect);
    try{
      const headers={'content-type':'application/json'};
      if(token)headers.authorization=`Bearer ${token}`;
      // Kilo sends dimensions even for a fixed-size model. Some LM Studio
      // versions reject that optional field. Omit only this redundant field;
      // do not truncate vectors, change models or retry arbitrary HTTP errors.
      const {dimensions,...payload}=body;
      const upstream=await fetch(new URL('embeddings',backend.href.replace(/\/?$/,'/')),
        {method:'POST',headers,body:JSON.stringify(payload),signal:abort.signal,redirect:'error'});
      if(!upstream.ok){await upstream.body?.cancel();throw new RouterError(upstream.status>=400&&upstream.status<600?upstream.status:502,'embedding_upstream_rejected','LM Studio rejected the managed embedding request. Check model readiness and local server logs.');}
      let size=0;const chunks=[];
      for await(const chunk of upstream.body){size+=chunk.length;if(size>RESPONSE_LIMIT){abort.abort();throw new RouterError(502,'embedding_response_too_large','Embedding response exceeded its transfer limit.');}chunks.push(chunk);}
      let result;try{result=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw new RouterError(502,'invalid_embedding_json','LM Studio returned invalid embedding JSON.');}
      if(!result||result.error||!Array.isArray(result.data)||result.data.length!==inputs.length)
        throw new RouterError(502,'invalid_embedding_response','LM Studio did not return one embedding for each input.');
      const indexes=new Set();
      for(const item of result.data){
        if(!item||!Number.isInteger(item.index)||item.index<0||item.index>=inputs.length||indexes.has(item.index))
          throw new RouterError(502,'invalid_embedding_index','LM Studio returned invalid or duplicate embedding indices.');
        indexes.add(item.index);
        let vector=item.embedding;
        if(typeof vector==='string'&&/^[A-Za-z0-9+/]{4096}$/.test(vector)){
          const bytes=Buffer.from(vector,'base64');vector=Array.from({length:768},(_,i)=>bytes.readFloatLE(i*4));
        }
        if(!Array.isArray(vector)||vector.length!==768||!vector.every(Number.isFinite)||!vector.some(value=>value!==0))
          throw new RouterError(502,'invalid_embedding_vector','LM Studio must return finite, nonzero vectors with exactly 768 dimensions.');
      }
      log({event:'embedding_completed',modelId:embeddingId,status:200});
      json(res,200,result);
    }catch(error){
      log({event:'embedding_failed',code:error.code||'embedding_request_failed'});errorResponse(res,error);
    }finally{
      embeddingRequests--;clearTimeout(deadline);res.removeListener('close',disconnect);req.removeListener('aborted',disconnect);
    }
  }
  async function handle(req,res){
    // No CORS grants: browser pages cannot silently submit authenticated JSON.
    if(req.headers.origin)throw new RouterError(403,'browser_origin_denied','Browser-origin requests are not supported by this endpoint.');
    if(token&&!equalSecret(req.headers.authorization,`Bearer ${token}`))throw new RouterError(401,'authentication_required','The configured local API token is required.');
    if(req.method==='GET'&&req.url==='/health'){
      json(res,fatal?503:200,{service:'shadow-local-model-router',version:ROUTER_VERSION,identity,pid:process.pid,
        configDigest,ready:!fatal&&!shuttingDown,activeAlias,busy:busy||embeddingRequests>0,queued:queue.length,embeddingRequests,
        currentRequest,lastError,
        models:[...profiles.values()].map(p=>({id:p.RouteId,context:p.ContextLength,output:p.OutputLimit,verification:p.VerificationState||'Verified'}))});return;
    }
    if(req.method==='POST'&&req.url==='/admin/shutdown'){
      if(!controlToken||!equalSecret(req.headers['x-shadow-control'],controlToken))throw new RouterError(403,'control_denied','A valid local control token is required.');
      if(busy||queue.length||embeddingRequests)throw new RouterError(409,'router_busy','The router has active or queued work. Finish it before restarting.');
      shuttingDown=true;json(res,200,{stopping:true});server.close();server.closeIdleConnections();return;
    }
    if(req.method==='GET'&&req.url==='/v1/models'){
      json(res,200,{object:'list',data:[...profiles.values()].map(p=>({id:p.RouteId,object:'model',created:0,owned_by:'local-shadow-pool'}))});return;
    }
    if(req.method==='POST'&&req.url==='/v1/embeddings'){await embeddings(req,res);return;}
    if(req.method!=='POST'||req.url!=='/v1/chat/completions')throw new RouterError(404,'endpoint_not_supported','Only local models, chat completions and managed embeddings are exposed.');
    if(shuttingDown||fatal)throw new RouterError(503,'router_unavailable','The local router needs a deliberate restart after its recorded controller failure.');
    const body=await readBody(req);
    if(!body||typeof body!=='object'||Array.isArray(body)||!Array.isArray(body.messages)||!body.messages.length)
      throw new RouterError(400,'invalid_messages','A nonempty messages array is required.');
    const profile=profiles.get(body.model);
    if(!profile)throw new RouterError(400,'model_not_provisioned','The requested model is not in this verified local pool.');
    for(const key of Object.keys(body)){if(!ALLOWED_FIELDS.has(key))throw new RouterError(400,'unsupported_field',`Unsupported chat field: ${key}`);}
    if(body.n!==undefined&&body.n!==1)throw new RouterError(400,'multiple_predictions_denied','Only one prediction per request is supported.');
    if(body.stream!==undefined&&typeof body.stream!=='boolean')throw new RouterError(400,'invalid_stream','stream must be a boolean.');
    for(const key of ['max_tokens','max_completion_tokens']){
      if(body[key]!==undefined&&(!Number.isInteger(body[key])||body[key]<1||body[key]>profile.OutputLimit))
        throw new RouterError(400,'output_limit_exceeded','Requested output exceeds the verified model output budget.');
    }
    if(body.max_tokens===undefined&&body.max_completion_tokens===undefined)body.max_tokens=profile.OutputLimit;
    if(queue.length>=maxQueued)throw new RouterError(429,'queue_full','The single-GPU request queue is full. Retry after current work completes.');
    const abort=new AbortController();
    const requestId=randomUUID(),requestStarted=Date.now();
    const lastUser=[...body.messages].reverse().find(m=>m?.role==='user');
    const userText=typeof lastUser?.content==='string'?lastUser.content:Array.isArray(lastUser?.content)?lastUser.content.filter(p=>p?.type==='text').map(p=>p.text).join('\n'):'';
    const probe=/LOKIENTE_ACCEPTANCE_[a-f0-9]{32}/.exec(userText)?.[0];
    const probeHash=probe?createHash('sha256').update(probe).digest('hex'):undefined;
    let probeTail='',probeReplyMatched=false;
    const observeReply=text=>{
      if(!probe||typeof text!=='string')return;
      const combined=probeTail+text;if(combined.includes(probe))probeReplyMatched=true;
      probeTail=combined.slice(-probe.length);
    };
    // A deadline also has to answer a still-open client while it is queued or
    // waiting for the controller. Merely aborting fetch leaves those clients
    // hanging, because no fetch exists yet and the later job is skipped.
    const deadline=setTimeout(()=>{
      const error=new RouterError(504,'request_timeout','The local request deadline was exceeded.');
      lastError={alias:profile.Alias,code:error.code,utc:new Date().toISOString()};
      log({event:'request_timed_out',alias:profile.Alias,code:error.code});
      abort.abort(error);errorResponse(res,error);
    },requestTimeoutMs);
    const disconnect=()=>{if(!res.writableFinished)abort.abort(new Error('Client disconnected.'));};
    res.once('close',disconnect);req.once('aborted',disconnect);
    enqueue(async()=>{
      try{
        if(abort.signal.aborted)return;
        if(fatal)throw new RouterError(503,'controller_failed','The local model controller requires attention.');
        currentRequest={alias:profile.Alias,phase:'Loading',startedAtUtc:new Date().toISOString()};
        log({event:'model_switch_started',alias:profile.Alias,requestId,probeHash});
        // Do not abort an in-progress model load when the client disconnects.
        // Wait for its settled result; otherwise a second request could race it.
        const state=await switchModel(profile);
        if(state.Status!=='Ready'||state.Alias!==profile.Alias||state.ModelId!==profile.InstanceId||state.ContextLength!==profile.ContextLength||state.Parallel!==1)
          throw new RouterError(503,'switch_verification_failed','The loaded model does not match the verified pool profile.');
        if(profile.VerificationState==='Deferred'&&state.VerificationState!=='Verified')
          throw new RouterError(503,'model_unverified','The local model has not passed verification yet.');
        if(state.VerificationState==='Verified'){
          profile.VerificationState='Verified';
          profile.SmokeTests={Chat:'Passed',ToolCall:'Passed',ToolResultRoundTrip:'Passed'};
        }
        activeAlias=profile.Alias;
        currentRequest={...currentRequest,phase:'Generating'};
        log({event:'model_switch_ready',alias:profile.Alias});
        if(abort.signal.aborted)return;
        const headers={'content-type':'application/json'};
        if(token)headers.authorization=`Bearer ${token}`;
        const upstream=await fetch(new URL('chat/completions',backend.href.replace(/\/?$/,'/')),
          {method:'POST',headers,body:JSON.stringify({...body,model:state.ModelId}),signal:abort.signal,redirect:'error'});
        if(!upstream.ok){await upstream.body?.cancel();throw new RouterError(upstream.status>=400&&upstream.status<600?upstream.status:502,'upstream_rejected','LM Studio rejected the request. Check its local status; no cloud fallback was attempted.');}
        if(body.stream){
          if(!upstream.headers.get('content-type')?.includes('text/event-stream')){await upstream.body?.cancel();throw new RouterError(502,'invalid_stream_type','LM Studio did not return an event stream.');}
          res.writeHead(200,{'content-type':'text/event-stream','cache-control':'no-cache','x-accel-buffering':'no'});
          let tail='',done=false,eventError=false,bytes=0;
          const decoder=new TextDecoder();
          for await(const chunk of upstream.body){
            bytes+=chunk.length;tail+=decoder.decode(chunk,{stream:true});
            let newline;
            while((newline=tail.indexOf('\n'))>=0){
              const line=tail.slice(0,newline).trimEnd();tail=tail.slice(newline+1);
              if(line.startsWith('data:')){
                const data=line.slice(5).trim();
                if(data==='[DONE]')done=true;
                else if(data){try{const event=JSON.parse(data);if(event.error)eventError=true;observeReply(event.choices?.[0]?.delta?.content);}catch{eventError=true;}}
              }
            }
            if(tail.length>1024*1024)throw new RouterError(502,'invalid_stream_frame','LM Studio returned an oversized event frame.');
            // The close handler aborts this signal. A cancellable single wait
            // removes its listeners after every drain instead of accumulating
            // losing `close` listeners over a long streamed response.
            if(!res.write(chunk))await once(res,'drain',{signal:abort.signal});
          }
          if(!bytes||!done||eventError)throw new RouterError(502,'incomplete_stream','LM Studio did not complete a valid prediction stream.');
          log({event:'request_completed',alias:profile.Alias,modelId:state.ModelId,requestId,probeHash,probeReplyMatched,elapsedMs:Date.now()-requestStarted,status:200});
          res.end();
        }else{
          let size=0;const chunks=[];
          for await(const chunk of upstream.body){size+=chunk.length;if(size>RESPONSE_LIMIT){abort.abort();throw new RouterError(502,'response_too_large','Local response exceeded its transfer limit.');}chunks.push(chunk);}
          let result;try{result=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw new RouterError(502,'invalid_upstream_json','LM Studio returned invalid JSON.');}
          if(result.error||!Array.isArray(result.choices)||!result.choices.length)throw new RouterError(502,'invalid_completion','LM Studio did not return a valid completion.');
          observeReply(result.choices[0]?.message?.content);
          log({event:'request_completed',alias:profile.Alias,modelId:state.ModelId,requestId,probeHash,probeReplyMatched,elapsedMs:Date.now()-requestStarted,status:200});
          json(res,200,result);
        }
      }catch(e){
        lastError={alias:profile.Alias,code:e.code||'request_aborted_or_failed',utc:new Date().toISOString()};
        if(e.fatal){fatal=e.code||'controller_failed';log({event:'controller_failed',code:fatal});}
        if(['model_memory_unavailable','model_unverified','model_runtime_incompatible','model_load_failed'].includes(e.code)){
          profile.VerificationState='Deferred';
          const status=e.code==='model_unverified'?'NotVerified':'NotRun';
          profile.SmokeTests={Chat:status,ToolCall:status,ToolResultRoundTrip:status};
        }
        // Record metadata only, never prompts, completions, headers or tokens.
        log({event:'request_failed',alias:profile.Alias,code:e.code||'request_aborted_or_failed',requestId,probeHash});
        errorResponse(res,e);
      }finally{currentRequest=null;clearTimeout(deadline);res.removeListener('close',disconnect);req.removeListener('aborted',disconnect);}
    });
  }
  return server;
}

export function makePowerShellSwitcher({installRoot,pwsh,switchScript,timeoutMs=900000}){
  return async profile=>{
    const temporary=path.join(installRoot,'runtime','router-work');await mkdir(temporary,{recursive:true});
    const resultPath=path.join(temporary,`${randomUUID()}.json`);
    try{
      const exitCode=await new Promise((resolve,reject)=>{
        const child=spawn(pwsh,['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',switchScript,'-InstallRoot',installRoot,'-Alias',profile.Alias,'-ResultPath',resultPath],
          {shell:false,windowsHide:true,stdio:['ignore','ignore','ignore'],env:process.env});
        // On timeout stop accepting new work. Do not kill an uncertain model load
        // and then start a competing one; the controller retains its own OS lock.
        const timer=setTimeout(()=>reject(new RouterError(503,'controller_timeout','Model loading exceeded its deadline. Finish or inspect the controller before restarting.',true)),timeoutMs);
        child.once('error',()=>{clearTimeout(timer);reject(new RouterError(503,'controller_start_failed','The local model controller could not be started.'));});
        child.once('close',code=>{clearTimeout(timer);resolve(code);});
      });
      let state;try{state=JSON.parse(await readFile(resultPath,'utf8'));}catch{
        if(exitCode!==0)throw new RouterError(503,'controller_rejected','The model switch was refused. Inspect local model ownership, memory and busy state.');
        throw new RouterError(503,'controller_result_missing','The controller did not provide a valid verification result.');
      }
      if(exitCode!==0){
        if(state?.Status==='Error'&&state.Code==='controller_timeout')
          throw new RouterError(504,'controller_timeout','LM Studio model loading or command output exceeded its deadline. Inspect LM Studio before restarting LoKiEnte; another load will not be started automatically.',true);
        if(state?.Status==='Error'&&state.Code==='controller_check_timeout')
          throw new RouterError(504,'controller_check_timeout','An LM Studio status, catalog or memory check exceeded its deadline. Check LM Studio responsiveness and runtime/model-switch-failure.json, then retry.');
        if(state?.Status==='Error'&&state.Code==='runtime_incompatible')
          throw new RouterError(503,'model_runtime_incompatible','The selected LM Studio runtime does not support this model architecture. Select or update a compatible GPU runtime in LM Studio, then retry. More memory cannot fix this. See runtime/pool-logs.');
        if(state?.Status==='Error'&&state.Code==='model_load_failed')
          throw new RouterError(503,'model_load_failed','LM Studio rejected the selected model load. Check the local model file, runtime and runtime/pool-logs, then retry.');
        if(state?.Status==='Error'&&state.Code==='model_conflict')
          throw new RouterError(503,'model_conflict','An external or manually loaded model blocks the managed model pool. Finish its work, unload it explicitly in LM Studio, then retry.');
        if(state?.Status==='Error'&&state.Code==='model_busy')
          throw new RouterError(503,'model_busy','The managed model is still busy or its idle state is unknown. Wait for active requests to finish, then retry.');
        if(state?.Status==='Error'&&state.Code==='backend_not_loopback')
          throw new RouterError(503,'backend_not_loopback','The LM Studio server is not bound exclusively to loopback. Disable serving on the local network and bind it to 127.0.0.1, then retry.');
        if(state?.Status==='Error'&&state.Code==='backend_authentication')
          throw new RouterError(503,'backend_authentication','LM Studio denied API access. Set its token in the configured user environment variable and restart LoKiEnte; authentication stays enabled.');
        if(state?.Status==='Error'&&state.Code==='resource_fit')
          throw new RouterError(503,'model_memory_unavailable','The local model cannot currently load. Free memory and retry; the model file is preserved.');
        if(state?.Status==='Error'&&state.Code==='model_unverified')
          throw new RouterError(503,'model_unverified','The local model failed the chat or tool test. Check local logs.');
        throw new RouterError(503,'controller_rejected','The model switch was refused. Read runtime/model-switch-failure.json for the local cause and script location.');
      }
      return state;
    }finally{await unlink(resultPath).catch(()=>{});}
  };
}

async function main(){
  const args=new Map();
  for(let i=2;i<process.argv.length;i+=2){if(!process.argv[i]?.startsWith('--')||process.argv[i+1]===undefined)throw new Error('Expected named arguments.');args.set(process.argv[i],process.argv[i+1]);}
  const file=path.resolve(args.get('--config')||'');
  const raw=await readFile(file);const config=JSON.parse(raw.toString('utf8').replace(/^\uFEFF/,''));
  const port=Number(args.get('--port'));if(!Number.isInteger(port)||port<1024||port>65535)throw new Error('Invalid router port.');
  const advertised=loopbackUrl(config.RouterApiBaseUrl);
  if(Number(advertised.port||80)!==port||advertised.port===loopbackUrl(config.BackendApiBaseUrl).port)
    throw new Error('Router port must match its verified pool and differ from the backend.');
  const installRoot=path.dirname(path.dirname(file));
  const logPath=path.join(installRoot,'runtime','router-events.jsonl');
  const log=event=>void writeFile(logPath,JSON.stringify({utc:new Date().toISOString(),...event})+'\n',{flag:'a'}).catch(()=>{});
  const token=config.ApiTokenEnvironmentVariable?process.env[config.ApiTokenEnvironmentVariable]||'':'';
  const configDigest=args.get('--routing-digest');
  if(!/^[a-f0-9]{64}$/.test(configDigest||''))throw new Error('Missing routing contract digest.');
  const server=createModelRouter({config,configDigest,token,
    controlToken:process.env.SHADOW_LOCAL_ROUTER_CONTROL||'',log,
    switchModel:makePowerShellSwitcher({installRoot,pwsh:args.get('--pwsh'),switchScript:args.get('--switch-script')})});
  server.listen(port,'127.0.0.1');await once(server,'listening');
  log({event:'started',pid:process.pid,version:ROUTER_VERSION,port});
  server.on('close',()=>log({event:'stopped'}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  main().catch(()=>{process.stderr.write('Local model router could not start. Check its configuration and port.\n');process.exitCode=1;});
}
