import {test,expect} from "bun:test";
import {changeSessionModel} from "./session_model";
function fixture(){
 const session:any={provider:"local",model:"old",status:"completed",workspaceRoot:"kept",metadata:{}};
 const calls:any[]=[];
 const ctx={cline:{get:async()=>session,updateSessionConnection:async(id:any,patch:any)=>{calls.push([id,patch]);session.model=patch.modelId;}}};
 const peer={selectedSessionId:"chosen",sending:false};
 const deps={models:async()=>({models:[{id:"new",operation:"language"}]}),settings:{getProviderConfig:()=>({})}};
 return {ctx,peer,deps,calls,session};
}
test("model update retains session, workspace and history and never sends",async()=>{
 const f=fixture();const result=await changeSessionModel(f.ctx,f.peer,{sessionId:"chosen",provider:"local",model:"new"},f.deps);
 expect(result).toEqual({sessionId:"chosen",provider:"local",model:"new"});
 expect(f.calls).toEqual([["chosen",{modelId:"new"}]]);expect(f.session.workspaceRoot).toBe("kept");
});
for(const invalid of [{sessionId:"other",provider:"local",model:"new"},{sessionId:"chosen",provider:"other",model:"new"},{sessionId:"chosen",provider:"local",model:"unknown"}]){
 test("rejects unselected session, provider or unlisted model "+JSON.stringify(invalid),async()=>{const f=fixture();await expect(changeSessionModel(f.ctx,f.peer,invalid,f.deps)).rejects.toThrow();expect(f.calls).toHaveLength(0);});
}
test("running turn cannot change model",async()=>{const f=fixture();f.peer.sending=true;await expect(changeSessionModel(f.ctx,f.peer,{sessionId:"chosen",provider:"local",model:"new"},f.deps)).rejects.toThrow();expect(f.calls).toHaveLength(0);});

test("dormant session retains identity and history without a prompt",async()=>{
 const f:any=fixture(); const messages=[{role:"user",content:"kept"}]; let live=false; let resumed:any;
 f.ctx.cline.updateSessionConnection=async(_id:any,patch:any)=>{if(!live)throw new Error("session not found: chosen");f.session.model=patch.modelId;};
 f.ctx.cline.readMessages=async()=>messages;
 f.ctx.cline.start=async(input:any)=>{resumed=input;live=true;return {sessionId:"chosen"};};
 f.deps.resume=()=>({config:{cwd:"kept"},initialMessages:messages});
 await changeSessionModel(f.ctx,f.peer,{sessionId:"chosen",provider:"local",model:"new"},f.deps);
 expect(resumed.config.sessionId).toBe("chosen"); expect(resumed.prompt).toBeUndefined();
 expect(resumed.initialMessages).toEqual(messages); expect(resumed.toolPolicies["*"].autoApprove).toBe(false);
});
