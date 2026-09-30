import fs from 'fs'; import crypto from 'crypto';
const BASE='https://surveytool.stg.veevart.ai'; const ts=Date.now();
const sub=JSON.parse(fs.readFileSync('submit-template.json')); const dft=JSON.parse(fs.readFileSync('draft-template.json'));
const post=async(p,b)=>{const r=await fetch(BASE+p,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(b)});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j=t};return{s:r.status,j}};
const out={};
// A: legacy no-token, respondent WITHOUT draft -> 201
const a={...sub,respondentId:`qa-tr218-legacy-${ts}`}; delete a.draftToken;
out.A_legacy_no_draft=await post('/api/responses',a);
// B: create an active draft, then legacy no-token submit for same respondent -> rejected
const rid=`qa-tr218-active-${ts}`;
out.B1_draft_create=await post('/api/survey-drafts',{...dft,respondentId:rid,draftToken:crypto.randomUUID(),saveSequence:1});
const b={...sub,respondentId:rid}; delete b.draftToken;
out.B2_legacy_with_active_draft=await post('/api/responses',b);
for (const [k,v] of Object.entries(out)) console.log(k, v.s, JSON.stringify(v.j).slice(0,260));
fs.writeFileSync('api-checks.json',JSON.stringify({ts,out},null,1));
