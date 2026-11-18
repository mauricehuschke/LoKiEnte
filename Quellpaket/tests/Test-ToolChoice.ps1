#requires -Version 7.4
[CmdletBinding()]
param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $SourceRoot 'Runtime.ps1')
$node=(Get-Command node.exe -CommandType Application|Select-Object -First 1).Source
$serverCode=@'
const http=require('node:http');
const server=http.createServer((req,res)=>{
  let data='';
  req.on('data',part=>data+=part);
  req.on('end',()=>{
    let b;
    try { b=JSON.parse(data); } catch { res.writeHead(400);return res.end('{}'); }
    if(req.method!=='POST'||!req.url.endsWith('/chat/completions')){res.writeHead(404);return res.end('{}');}
    const send=(message)=>{res.setHeader('content-type','application/json');res.end(JSON.stringify({choices:[{message}]}));};
    if(!b.tools){
      const content=req.url.includes('/bad-chat/')?'incorrect':(req.url.includes('/quoted/')?'"LOCAL_READY"':'LOCAL_READY');
      return send({content});
    }
    if(b.tool_choice==='required'){
      if(b.tools.length!==1||b.tools[0].function.name!=='report_value'){res.writeHead(400);return res.end('{}');}
      const name=req.url.includes('/bad-tool/')?'other':'report_value';
      return send({content:null,tool_calls:[{id:'call-fixture',type:'function',function:{name,arguments:'{"value":17}'}}]});
    }
    if(b.tool_choice==='none'){
      const tool=b.messages.find(m=>m.role==='tool');
      const assistant=b.messages.find(m=>m.role==='assistant');
      if(!tool||tool.tool_call_id!=='call-fixture'||!assistant||assistant.tool_calls[0].id!=='call-fixture'){
        res.writeHead(400);return res.end('{}');
      }
      const content=req.url.includes('/bad-receipt/')?'incorrect':
        (req.url.includes('/prose/')?'Receipt: LOCAL_TOOL_OK':(req.url.includes('/quoted/')?'"LOCAL_TOOL_OK"':'LOCAL_TOOL_OK'));
      return send({content});
    }
    res.writeHead(400);res.end('{"error":"tool_choice must be required or none"}');
  });
});
server.listen(0,'127.0.0.1',()=>console.log(server.address().port));
'@
$start=[Diagnostics.ProcessStartInfo]::new()
$start.FileName=$node;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
$start.ArgumentList.Add('--eval');$start.ArgumentList.Add($serverCode)
$process=[Diagnostics.Process]::Start($start)
try{
    $read=$process.StandardOutput.ReadLineAsync()
    if(-not $read.Wait(10000)){throw 'Synthetic HTTP server startup timeout'}
    $port=[int]$read.Result
    if($port -le 0){throw 'Synthetic HTTP server did not start'}
    $base="http://127.0.0.1:$port"
    $result=Test-LrModelInference -ApiBaseUrl "$base/ok/v1" -ModelId 'fixture' -Headers @{}
    if($result.Chat -cne 'Passed' -or $result.ToolCall -cne 'Passed' -or $result.ToolResultRoundTrip -cne 'Passed'){
        throw 'Chat, required tool call or tool response was not verified'
    }
    $quoted=Test-LrModelInference -ApiBaseUrl "$base/quoted/v1" -ModelId 'fixture' -Headers @{}
    if($quoted.Chat -cne 'Passed' -or $quoted.ToolCall -cne 'Passed' -or $quoted.ToolResultRoundTrip -cne 'Passed'){
        throw 'Quoted exact chat and tool replies were not accepted'
    }
    $count=2
    foreach($case in @(
        @{Content='  "LOCAL_TOOL_OK"  ';Expected=$true},
        @{Content='local_tool_ok';Expected=$false},
        @{Content='"LOCAL_TOOL_OK';Expected=$false},
        @{Content='LOCAL_TOOL_OK and more';Expected=$false}
    )){
        if((Test-LrExactReply -Content $case.Content -Expected 'LOCAL_TOOL_OK') -ne $case.Expected){
            throw 'Token comparison accepted or rejected an incorrect reply'
        }
        $count++
    }
    foreach($case in @(
        @{Path='bad-chat';Pattern='Chat-Smoke-Test'},
        @{Path='bad-tool';Pattern='Kein eindeutiger'},
        @{Path='bad-receipt';Pattern='Tool-Antwort'},
        @{Path='prose';Pattern='Tool-Antwort'}
    )){
        $failure=$null
        try{$null=Test-LrModelInference -ApiBaseUrl "$base/$($case.Path)/v1" -ModelId 'fixture' -Headers @{}}catch{$failure=$_.Exception.Message}
        if(-not $failure -or $failure -notmatch $case.Pattern){throw "Invalid $($case.Path) response was not rejected"}
        $count++
    }
    [pscustomobject]@{suite='Tool choice and round trip';passed=$true;checks=$count}|ConvertTo-Json
}finally{
    if(-not $process.HasExited){$process.Kill();$process.WaitForExit()}
    $process.Dispose()
}
