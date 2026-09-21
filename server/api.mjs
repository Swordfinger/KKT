import {ensureUser,saveProfile,accountState,feed,setLike,dismiss,runMatching} from './service.mjs';
export function json(data,status=200,extra={}){return new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store',...extra}})}
export async function api(request,db,userId,{now=Math.floor(Date.now()/1000),schedule,authProvider='sites'}={}){
 const url=new URL(request.url);if(url.pathname==='/api/context')return json({authenticated:!!userId,authProvider});if(!userId)return json({error:'请先登录'},401);
 if(!['GET','HEAD'].includes(request.method)){if(request.headers.get('origin')!==url.origin)return json({error:'来源校验失败'},403);if(!request.headers.get('content-type')?.startsWith('application/json'))return json({error:'需要JSON请求'},415)}
 await ensureUser(db,userId,now);
 try{
 if(request.method==='GET'&&url.pathname==='/api/me')return json(await accountState(db,userId,now));
 if(request.method==='GET'&&url.pathname==='/api/recommendations'){if(schedule)schedule(runMatching(db,{now}));return json({items:await feed(db,userId,now)})}
 if(request.method==='GET'&&url.pathname==='/api/likes')return json({items:await feed(db,userId,now,'likes')});
 const raw=await request.text();if(raw.length>16000)return json({error:'提交内容过大'},413);let body={};try{body=raw?JSON.parse(raw):{}}catch{return json({error:'无效JSON'},400)}
 if(request.method==='PUT'&&url.pathname==='/api/profile'){await saveProfile(db,userId,body,now);await runMatching(db,{now});return json(await accountState(db,userId,now))}
 if(request.method==='POST'&&url.pathname==='/api/likes'){return json(await setLike(db,userId,body.targetId,true,now))}
 if(request.method==='DELETE'&&url.pathname==='/api/likes'){return json(await setLike(db,userId,body.targetId,false,now))}
 if(request.method==='POST'&&url.pathname==='/api/dismiss'){return json(await dismiss(db,userId,body.pairId))}
 return json({error:'接口不存在'},404);
 }catch(e){const message=e.message||'';const map={LIKE_LIMIT:'喜欢人数已达20人，请先取消一位',NOT_RECOMMENDED:'只能喜欢已推荐给你的用户',PROFILE_UNAVAILABLE:'对方已暂停匹配',NOT_FOUND:'推荐不存在',INVALID_LIKE:'无效的喜欢操作'};const code=Object.keys(map).find(k=>message.includes(k));if(code)return json({error:map[code],code},code==='NOT_FOUND'?404:409);if(/数据库|SQLITE|D1_ERROR/.test(message)){console.error('Database operation failed');return json({error:'服务暂时不可用，请稍后重试'},503)}return json({error:message},400)}
}
