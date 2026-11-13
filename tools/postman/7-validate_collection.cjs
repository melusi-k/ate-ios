const fs=require('fs'),vm=require('vm'),assert=require('assert');
const dir=__dirname, c=JSON.parse(fs.readFileSync(`${dir}/Ate.postman_collection.json`)), e=JSON.parse(fs.readFileSync(`${dir}/Staging.postman_environment.json`));
const requests=c.item.flatMap(f=>f.item), coverage=JSON.parse(fs.readFileSync(`${dir}/coverage.json`));
let checks=0;
const check=(v,m)=>{assert(v,m);checks++;};
check(c.info.schema==='https://schema.getpostman.com/json/collection/v2.1.0/collection.json','schema declaration');
check(requests.length===57,'request count');
check(new Set(requests.map(r=>r.name)).size===requests.length,'unique names');
check(coverage.filter(r=>r.included).length===requests.length,'coverage parity');
const baseline=Object.fromEntries(e.values.map(v=>[v.key,v.value]));
for(const [k,v] of Object.entries(baseline))if(/password|token|anon_key|jwt|verifier|email_code/.test(k)) check(v==='',`blank credential ${k}`);
function guard(item, overrides={}, headers={}) {
 const values={...baseline,...overrides};let skipped=false,error;
 const get=k=>values[k];
 const replace=s=>s.replace(/{{([^}]+)}}/g,(_,k)=>values[k]??(k==='$guid'?'00000000-0000-4000-8000-000000000001':''));
 const context={URL,atob,Date,require,pm:{execution:{skipRequest(){skipped=true;}},environment:{get,set(k,v){values[k]=v;}},variables:{get,replaceIn:replace},request:{url:{toString:()=>item.request.url},headers:{has:k=>Object.keys(headers).some(h=>h.toLowerCase()===k.toLowerCase())}}}};
 try{vm.runInNewContext(item.event.find(x=>x.listen==='prerequest').script.exec.join('\n'),context);}catch(e){error=e;}
 return {skipped,error,values};
}
const ready={supabase_url:'https://synthetic.supabase.co',approved_staging_host:'synthetic.supabase.co',anon_key:'sb_publishable_synthetic',user_id:'synthetic-id',access_token:'synthetic-token',synthetic_account_confirmed:'true'};
for(const r of requests){
 check(r.request.auth.type==='noauth','no inherited credentials');
 check(r.protocolProfileBehavior.followRedirects===false,'no credential redirect');
 for(const event of r.event){new vm.Script(event.script.exec.join('\n'));checks++;}
 check(guard(r).skipped,`default skip ${r.name}`);
 check(r.event.find(x=>x.listen==='test').script.exec.join('\n').includes('pm.response.to.have.status('),`strict status ${r.name}`);
 if(r.request.url.startsWith('{{supabase_url}}')){
  check(guard(r,{...ready,approved_staging_host:'other.invalid',allow_mutations:'true',allow_account_reset:'I_ACCEPT_SYNTHETIC_ACCOUNT_ERASURE'}).skipped,`wrong host ${r.name}`);
  check(guard(r,{...ready,target_environment:'production'}).skipped,`production marker ${r.name}`);
  check(guard(r,{...ready,anon_key:'sb_secret_forbidden'}).skipped,`secret key ${r.name}`);
 } else {
  check(!r.request.header.some(h=>/authorization|apikey/i.test(h.key)),`external no auth ${r.name}`);
  check(guard(r,{approved_external_host:'fixture.invalid'},{Authorization:'forbidden'}).skipped,`external secret guard ${r.name}`);
 }
}
for(const r of c.item.find(f=>f.name.startsWith('04')).item){
 check(guard(r,{...ready,allow_mutations:'true'}).skipped,`destructive latch ${r.name}`);
 const result=guard(r,{...ready,allow_mutations:'true',allow_account_reset:'I_ACCEPT_SYNTHETIC_ACCOUNT_ERASURE'});
 check(!result.skipped&&!result.error,`destructive opt-in ${r.name}: ${result.error}`);
}
for(const r of requests.filter(r=>r.name.startsWith('AI parse'))){check(guard(r,{...ready,allow_mutations:'true'}).skipped,'dormant AI skipped');}
// Execute key assertion scripts, including failing fixtures. No HTTP is performed.
function expect(value){
 const chain={};for(const k of ['to','be','have','an','a','and','at'])Object.defineProperty(chain,k,{get:()=>chain,configurable:true});
 chain.equal=x=>{assert.strictEqual(value,x);return chain};
 chain.property=k=>{assert(value!=null&&k in value);return chain};
 chain.least=x=>{assert(value>=x);return chain};
 chain.above=x=>{assert(value>x);return chain};
 chain.match=x=>{assert(x.test(value));return chain};
 chain.include=x=>{assert(value.includes(x));return chain};
 chain.length=x=>{assert.strictEqual(value.length,x);return chain};
 // Chai .a/.an are functions but also chain properties in syntax: pm.expect(x).to.be.a('number').
 for(const k of ['a','an'])Object.defineProperty(chain,k,{get:()=>type=>{assert(type==='array'?Array.isArray(value):typeof value===type);return chain;},configurable:true});
 return chain;
}
function assertions(name,code,body,variables={}){
 const r=requests.find(r=>r.name===name);let errors=[];
 const pm={test(n,f){try{f()}catch(e){errors.push(n+':'+e.message)}},expect,
 response:{code,json:()=>body,to:{have:{status:n=>assert.strictEqual(code,n)}},headers:{get:()=> 'GET, POST, OPTIONS'},text:()=> "synthetic response"},
 variables:{get:k=>variables[k]},environment:{set(){}}};
 vm.runInNewContext(r.event.find(e=>e.listen==='test').script.exec.join('\n'),{pm,Number,String});return errors;
}
check(assertions('05 Stale put must return PT409',409,{code:'PT409'}).length===0,'PT409 correct accepted');
check(assertions('05 Stale put must return PT409',409,{code:'40001'}).length>0,'serialization code rejected');
check(assertions('05 Stale put must return PT409',200,{code:'PT409'}).length>0,'wrong status rejected');
const retained={generation:3,rows:[{id:'postman-retained',updated_at:20,data:{title:'Synthetic retained'}}]};
check(assertions('08 Verify no mutation after conflicts',200,retained,{generation:'3'}).length===0,'unchanged retained accepted');
check(assertions('08 Verify no mutation after conflicts',200,{...retained,generation:4},{generation:'3'}).length>0,'wrong generation rejected');
check(assertions('08 Verify no mutation after conflicts',200,{generation:3,rows:[]},{generation:'3'}).length>0,'lost retained row rejected');
check(assertions('Atomic account snapshot',200,{generation:2**53,rows:[]}).length>0,'unsafe integer rejected');
for (const r of c.item.find(f=>f.name.startsWith('08')).item) check(assertions(r.name,200,{}).length===0,`external response assertions ${r.name}`);
console.log(`PASS: ${checks} offline collection checks across ${requests.length} requests. No network calls.`);
