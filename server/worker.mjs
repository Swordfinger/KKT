import {api,json} from './api.mjs';
import {runMatching} from './service.mjs';
import html from './web/index.html';
import script from './web/app.js';
import css from './web/styles.css';
export default {
 async fetch(request,env,ctx){const path=new URL(request.url).pathname;if(path.startsWith('/api/')){if(!env.DB)return json({error:'数据库尚未配置'},503);return api(request,env.DB,request.headers.get('oai-authenticated-user-id'),{authProvider:'sites',schedule:p=>ctx.waitUntil(p)})}const content={'/':[html,'text/html; charset=utf-8'],'/app.js':[script,'text/javascript; charset=utf-8'],'/styles.css':[css,'text/css; charset=utf-8']}[path];return content?new Response(content[0],{headers:{'Content-Type':content[1],'Cache-Control':'no-cache'}}):new Response('Not found',{status:404})},
 async scheduled(event,env,ctx){ctx.waitUntil(runMatching(env.DB))}
};
