import * as THREE from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {VRMLoaderPlugin, VRMUtils} from '@pixiv/three-vrm';

const MAX = 25 * 1024 * 1024;
// Standard TTS exposes playback events, not PCM. Keep that approximation
// explicit instead of animating from the user's microphone or claiming visemes.
export function mouthWeight(time,{speaking=false,level=0,metered=true}={}) {
  if(!speaking)return 0;
  if(metered)return Math.min(1,Math.max(0,Number(level)||0));
  return .12+.42*Math.abs(Math.sin(time*9.4))*Math.abs(Math.cos(time*2.1));
}
export function readAvatar(data) {
  if (data.byteLength < 28 || data.byteLength > MAX) throw Error('Invalid avatar size');
  const v = new DataView(data), n = v.getUint32(12, true);
  if (v.getUint32(0,true)!==0x46546c67 || v.getUint32(4,true)!==2 ||
      v.getUint32(8,true)!==data.byteLength || v.getUint32(16,true)!==0x4e4f534a ||
      n>2*1024*1024 || n+28>data.byteLength ||
      v.getUint32(n+24,true)!==0x004e4942 || n+28+v.getUint32(n+20,true)!==data.byteLength)
    throw Error('Invalid avatar container');
  const j=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(new Uint8Array(data,20,n)));
  const vrm=j.extensions?.VRMC_vrm ?? j.extensions?.VRM;
  const bones=Array.isArray(vrm?.humanoid?.humanBones)
    ? Object.fromEntries(vrm.humanoid.humanBones.map(b=>[b.bone,b])) : vrm?.humanoid?.humanBones;
  for(const name of ['hips','spine','head','leftUpperArm','rightUpperArm','leftLowerArm','rightLowerArm'])
    if(!Number.isInteger(bones?.[name]?.node) || !j.nodes?.[bones[name].node]) throw Error('Invalid humanoid rig');
  if(j.buffers?.length!==1 || j.buffers[0].uri || !Number.isInteger(j.buffers[0].byteLength) ||
      j.buffers[0].byteLength<0 || j.buffers[0].byteLength>data.byteLength-n-28 ||
      (j.nodes?.length??0)>512 || (j.images?.length??0)>32 ||
      (j.accessors??[]).some(a=>!Number.isSafeInteger(a.count)||a.count<0) ||
      (j.accessors??[]).reduce((a,b)=>a+b.count,0)>5_000_000)
    throw Error('External or oversized avatar resources');
  for(const image of j.images??[]) {
    const b=j.bufferViews?.[image.bufferView];
    if(image.uri || !Number.isInteger(image.bufferView) || !b || (b.buffer??0)!==0 ||
        !Number.isInteger(b.byteLength) || b.byteLength<0 || !Number.isInteger(b.byteOffset??0) ||
        (b.byteOffset??0)<0 || (b.byteOffset??0)+b.byteLength>j.buffers[0].byteLength ||
        !['image/png','image/jpeg','image/webp'].includes(image.mimeType)) throw Error('Invalid avatar texture');
  }
  return {json:j,start:n+28};
}

export async function createAvatar(canvas,data) {
  const {json:j,start}=readAvatar(data);
  let pixels=0;
  for(const im of j.images??[]) {
    const b=j.bufferViews[im.bufferView];
    const bmp=await createImageBitmap(new Blob([data.slice(start+(b.byteOffset??0),start+(b.byteOffset??0)+b.byteLength)],{type:im.mimeType}));
    const invalid=bmp.width>4096 || bmp.height>4096 || (pixels+=bmp.width*bmp.height)>32*1024*1024;
    bmp.close(); if(invalid) throw Error('Avatar texture budget exceeded');
  }
  const manager=new THREE.LoadingManager();
  manager.setURLModifier(u=>{if(!u.startsWith('blob:'))throw Error('External resources blocked');return u;});
  const loader=new GLTFLoader(manager); loader.register(p=>new VRMLoaderPlugin(p));
  const gltf=await loader.parseAsync(data,''); const vrm=gltf.userData.vrm;
  if(!vrm){VRMUtils.deepDispose(gltf.scene);throw Error('Unsupported VRM');}
  VRMUtils.rotateVRM0(vrm);
  let renderer;
  try{renderer=new THREE.WebGLRenderer({canvas,alpha:true,antialias:true,powerPreference:'low-power'});}
  catch(e){VRMUtils.deepDispose(vrm.scene);throw e;}
  renderer.setPixelRatio(Math.min(window.devicePixelRatio||1,1.5));
  renderer.setClearColor(0,0); renderer.outputColorSpace=THREE.SRGBColorSpace;
  const scene=new THREE.Scene();scene.add(vrm.scene,new THREE.HemisphereLight(0xffffff,0x9ca3af,2));
  const light=new THREE.DirectionalLight(0xffffff,2.2);light.position.set(-1,2,3);scene.add(light);
  const bone=n=>vrm.humanoid.getNormalizedBoneNode(n);
  const mirror=vrm.meta.metaVersion==='0'?-1:1;
  if(bone('leftUpperArm'))bone('leftUpperArm').rotation.z=-1.35*mirror;
  if(bone('rightUpperArm'))bone('rightUpperArm').rotation.z=1.35*mirror;
  vrm.update(0);vrm.scene.updateMatrixWorld(true);
  const head=bone('head')?.getWorldPosition(new THREE.Vector3())??new THREE.Vector3(0,1.5,0);
  const hips=bone('hips')?.getWorldPosition(new THREE.Vector3())??new THREE.Vector3(0,.8,0);
  const height=Math.max(.4,head.y-hips.y), center=head.clone().add(new THREE.Vector3(0,-height*.18,0));
  const camera=new THREE.PerspectiveCamera(30,1,.01,50);
  const expressions=vrm.expressionManager;
  let elapsed=0,disposed=false,lastWidth=0,lastHeight=0;
  return {
    capabilities:{mouth:!!expressions?.getExpression('aa'),blink:!!expressions?.getExpression('blink')},
    render(dt,{speaking=false,level=0,metered=true,reducedMotion=false}={}) {
      if(disposed)return;
      elapsed+=Math.min(.1,Math.max(0,dt));
      const w=Math.max(1,canvas.clientWidth),h=Math.max(1,canvas.clientHeight);
      if(w!==lastWidth||h!==lastHeight){
        lastWidth=w;lastHeight=h;renderer.setSize(w,h,false);
        camera.aspect=w/h;camera.updateProjectionMatrix();
      }
      const distance=height*.8/Math.tan(Math.PI/12)*Math.max(1,1/camera.aspect);
      camera.position.copy(center).add(new THREE.Vector3(0,0,distance));camera.lookAt(center);
      expressions?.setValue('aa',mouthWeight(elapsed,{speaking,level,metered}));
      const blink=reducedMotion?0:Math.max(0,1-Math.abs((elapsed%4.6)-4.45)/.09);
      if(expressions?.getExpression('blink'))expressions.setValue('blink',blink);
      else{expressions?.setValue('blinkLeft',blink);expressions?.setValue('blinkRight',blink);}
      vrm.update(Math.min(.1,Math.max(0,dt)));renderer.render(scene,camera);
    },
    dispose(){disposed=true;VRMUtils.deepDispose(vrm.scene);renderer.dispose();renderer.forceContextLoss();}
  };
}

if(typeof window!=='undefined' && document.getElementById('avatar')) {
  let chunks=[],bytes=0,avatar=null,dead=false,frame=0,last=0;
  let signals={speaking:false,level:0,reducedMotion:false,active:true};
  const canvas=document.getElementById('avatar');
  const stop=()=>{cancelAnimationFrame(frame);frame=0;last=0;};
  const tick=t=>{
    frame=0;if(dead||document.hidden||!signals.active)return;
    if(t-last>=1000/30){avatar?.render(last?(t-last)/1000:0,signals);last=t;}
    frame=requestAnimationFrame(tick);
  };
  const resume=()=>{if(avatar&&!dead&&!document.hidden&&signals.active&&!frame)frame=requestAnimationFrame(tick);};
  document.addEventListener('visibilitychange',()=>{stop();resume();});
  canvas.addEventListener('webglcontextlost',e=>{e.preventDefault();stop();dead=true;});
  window.conduitAvatar={
    append(part){if(dead||avatar||typeof part!=='string'||part.length>131072||(bytes+=part.length)>Math.ceil(MAX/3)*4)throw Error('Invalid transfer');chunks.push(part);},
    async load(){try{const raw=atob(chunks.join(''));chunks=[];const data=Uint8Array.from(raw,c=>c.charCodeAt(0)).buffer;
      const loaded=await createAvatar(canvas,data);if(dead){loaded.dispose();return false;}avatar=loaded;
      // Report readiness only after the first real WebGL draw succeeds.
      avatar.render(0,{speaking:false,reducedMotion:true});resume();return {ok:true,...avatar.capabilities};
    }catch(_){chunks=[];return {ok:false};}},
    signal(value){signals={...signals,...value};stop();if(!signals.active)avatar?.render(0,{speaking:false,reducedMotion:true});else resume();},
    dispose(){dead=true;chunks=[];stop();avatar?.dispose();avatar=null;}
  };
}
