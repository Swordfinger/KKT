import http from 'node:http';
import {readFileSync,mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {randomBytes,createHash,scrypt as scryptCallback,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
import {database,migrate} from './sqlite.mjs';
import {api,json} from './api.mjs';
import {runMatching} from './service.mjs';
const scrypt=promisify(scryptCallback),base=fileURLToPath(new URL('../',import.meta.url));
mkdirSync(base+'data',{recursive:true});const db=database(process.env.DATABASE_PATH||base+'data/yujian.sqlite');migrate(db);
const attempts=new Map(),now=()=>Math.floor(Date.now()/1000),hash=t=>createHash('sha256').update(t).digest('hex');
const cookie=(token,secure,expire=false)=>`yujian_session=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${expire?0:2592000}${secure?'; Secure':''}`;
async function authenticate(req){const token=(req.headers.cookie||'').match(/(?:^|;\s*)yujian_session=([a-f0-9]{64})(?:;|$)/)?.[1];if(!token)return null;const s=await db.prepare('SELECT user_id FROM sessions WHERE token_hash=? AND expires_at>?').bind(hash(token),now()).first();return s?.user_id||null}
async function auth(request,ip){
 const url=new URL(request.url);if(request.method!=='POST'||request.headers.get('origin')!==url.origin||!request.headers.get('content-type')?.startsWith('application/json'))return json({error:'请求来源无效'},403);
 const raw=await request.text();if(raw.length>2000)return json({error:'请求过大'},413);let body;try{body=JSON.parse(raw)}catch{return json({error:'格式不正确'},400)}
 if(url.pathname==='/api/auth/logout'){const token=(request.headers.get('cookie')||'').match(/yujian_session=([a-f0-9]{64})/)?.[1];if(token)await db.prepare('DELETE FROM sessions WHERE token_hash=?').bind(hash(token)).run();return json({ok:true},200,{'Set-Cookie':cookie('',url.protocol==='https:',true)})}
 const entry=attempts.get(ip)||{start:now(),count:0};if(now()-entry.start>=60){entry.start=now();entry.count=0}entry.count++;attempts.set(ip,entry);if(entry.count>12)return json({error:'尝试过于频繁，请一分钟后再试'},429);
 const username=String(body.username||'').toLowerCase(),password=body.password;
 if(!/^[a-z0-9_]{3,32}$/.test(username)||typeof password!=='string'||password.length<10||password.length>128)return json({error:'账号需3–32位字母、数字或下划线，密码需10–128位'},400);
 let user=await db.prepare('SELECT id,password_hash FROM users WHERE username=?').bind(username).first();
 if(url.pathname==='/api/auth/register'){
 if(user)return json({error:'此账号已存在'},409);const salt=randomBytes(16).toString('hex'),key=Buffer.from(await scrypt(password,salt,64)).toString('hex');const id=crypto.randomUUID();try{await db.prepare('INSERT INTO users(id,username,password_hash,updated_at) VALUES(?,?,?,?)').bind(id,username,salt+':'+key,now()).run()}catch{return json({error:'账号已存在，请直接登录'},409)}user={id};
 }else if(url.pathname==='/api/auth/login'){
 const [salt,stored]=(user?.password_hash||'00000000000000000000000000000000:'+('0'.repeat(128))).split(':');const key=Buffer.from(await scrypt(password,salt,64));if(!user||!timingSafeEqual(key,Buffer.from(stored,'hex')))return json({error:'账号或密码错误'},401);
 }else return json({error:'接口不存在'},404);
 const token=randomBytes(32).toString('hex');await db.prepare('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)').bind(hash(token),user.id,now()+2592000).run();return json({ok:true},200,{'Set-Cookie':cookie(token,url.protocol==='https:')});
}
const server=http.createServer(async(req,res)=>{
 try{
 const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>20000){res.writeHead(413).end();return}chunks.push(chunk)}
 const origin=process.env.PUBLIC_ORIGIN||`http://${req.headers.host}`;const url=new URL(req.url,origin);if(url.origin!==new URL(origin).origin){res.writeHead(400).end();return}
 const request=new Request(url,{method:req.method,headers:req.headers,body:['GET','HEAD'].includes(req.method)?undefined:Buffer.concat(chunks)});let response;
 if(url.pathname.startsWith('/api/auth/'))response=await auth(request,req.socket.remoteAddress);
 else if(url.pathname.startsWith('/api/'))response=await api(request,db,await authenticate(req),{authProvider:'local',schedule:p=>p.catch(()=>console.error('Matching temporarily unavailable'))});
 else{const files={'/':['index.html','text/html; charset=utf-8'],'/app.js':['app.js','text/javascript; charset=utf-8'],'/styles.css':['styles.css','text/css; charset=utf-8']};const file=files[url.pathname];response=file?new Response(readFileSync(base+'server/web/'+file[0]),{headers:{'Content-Type':file[1]}}):new Response('Not found',{status:404})}
 res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()));
 }catch{res.writeHead(500,{'Content-Type':'application/json'});res.end(JSON.stringify({error:'服务暂时不可用'}))}
});
const timer=setInterval(()=>{runMatching(db).catch(()=>console.error('Matching temporarily unavailable'));db.prepare('DELETE FROM sessions WHERE expires_at<?').bind(now()).run();for(const [key,item]of attempts)if(now()-item.start>120)attempts.delete(key)},60000);timer.unref();
server.listen(Number(process.env.PORT||4175),process.env.HOST||'127.0.0.1',()=>{console.log('Local: http://127.0.0.1:'+String(process.env.PORT||4175));runMatching(db).catch(()=>console.error('Matching temporarily unavailable'))});
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{clearInterval(timer);server.close(()=>{db.close();process.exit(0)})});
