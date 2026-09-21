import Bazi from './bazi.cjs';
export const RECOMMENDATION_LIMIT=20,LIKE_LIMIT=20;
export const shanghaiDay=(seconds=Date.now()/1000)=>new Date(seconds*1000+8*3600*1000).toISOString().slice(0,10);
export function ageOn(date,day=shanghaiDay()){return Number(day.slice(0,4))-Number(date.slice(0,4))-(day.slice(5)<date.slice(5)?1:0)}
export function validateProfile(input,now){
 const {nickname,birthDate,birthTime,city='',bio='',gender='unspecified',seeking='any',minAge=18,maxAge=100}=input;
 if(typeof nickname!=='string'||!nickname.trim()||nickname.length>24)throw new Error('请填写24字以内的昵称');
 const chart=Bazi.chart({date:birthDate,time:birthTime});const age=ageOn(birthDate,shanghaiDay(now));if(age<18||age>100)throw new Error('仅限18岁及以上成年人，请检查生辰');
 if(!['male','female','other','unspecified'].includes(gender)||!['any','male','female','other'].includes(seeking))throw new Error('性别或交友偏好无效');
 if(!Number.isInteger(minAge)||!Number.isInteger(maxAge)||minAge<18||maxAge>100||minAge>maxAge)throw new Error('请检查期待的年龄范围');
 if(typeof city!=='string'||city.length>30||typeof bio!=='string'||bio.length>300)throw new Error('城市或介绍过长');
 if(!Array.isArray(input.interests)||input.interests.length>10||input.interests.some(t=>typeof t!=='string'||t.length>20))throw new Error('兴趣格式不正确');
 if(typeof input.consent!=='boolean')throw new Error('请选择是否参与匹配');
 return {nickname:nickname.trim(),birthDate,birthTime,chart:JSON.stringify(chart),city:city.trim(),bio:bio.trim(),gender,seeking,minAge,maxAge,interests:JSON.stringify([...new Set(input.interests.map(t=>t.trim()).filter(Boolean))]),consent:input.consent?1:0};
}
export async function ensureUser(db,id,now){await db.prepare('INSERT INTO users(id,updated_at) VALUES(?,?) ON CONFLICT(id) DO NOTHING').bind(id,now).run()}
export async function saveProfile(db,id,input,now){const p=validateProfile(input,now);const statements=[db.prepare('UPDATE users SET nickname=?,birth_date=?,birth_time=?,chart=?,city=?,bio=?,gender=?,seeking=?,min_age=?,max_age=?,interests=?,consent=?,version=version+1,updated_at=? WHERE id=?').bind(p.nickname,p.birthDate,p.birthTime,p.chart,p.city,p.bio,p.gender,p.seeking,p.minAge,p.maxAge,p.interests,p.consent,now,id)];if(!p.consent)statements.push(db.prepare('UPDATE likes SET active=0 WHERE sender=? OR recipient=?').bind(id,id));await db.batch(statements);return p}
function publicProfile(p,day){return {id:p.id,nickname:p.nickname,age:ageOn(p.birth_date,day),city:p.city,bio:p.bio,interests:JSON.parse(p.interests),gender:p.gender}}
export async function accountState(db,id,now){
 const day=shanghaiDay(now),p=await db.prepare('SELECT * FROM users WHERE id=?').bind(id).first();
 const used=await db.prepare('SELECT count(*) n FROM recommendation_pairs WHERE day=? AND (a=? OR b=?)').bind(day,id,id).first();
 const liked=await db.prepare('SELECT count(*) n FROM likes WHERE sender=? AND active=1').bind(id).first();
 return {day,timezone:'Asia/Shanghai',recommendationUsed:used.n,recommendationLimit:20,likeUsed:liked.n,likeLimit:20,profile:p?{nickname:p.nickname,birthDate:p.birth_date,birthTime:p.birth_time,chart:p.chart?JSON.parse(p.chart):null,city:p.city,bio:p.bio,interests:JSON.parse(p.interests),gender:p.gender,seeking:p.seeking,minAge:p.min_age,maxAge:p.max_age,consent:!!p.consent}:null};
}
export async function feed(db,id,now,kind='today'){
 const day=shanghaiDay(now);let rows;
 if(kind==='likes')rows=await db.prepare(`SELECT u.*,r.score,r.reasons,r.day,r.id pair_id,1 liked,EXISTS(SELECT 1 FROM likes l2 WHERE l2.sender=u.id AND l2.recipient=? AND l2.active=1) mutual FROM likes l JOIN users u ON u.id=l.recipient JOIN recommendation_pairs r ON (r.a=l.sender AND r.b=l.recipient) OR (r.b=l.sender AND r.a=l.recipient) WHERE l.sender=? AND l.active=1 AND u.consent=1 ORDER BY l.created_at DESC`).bind(id,id).all();
 else rows=await db.prepare(`SELECT u.*,r.score,r.reasons,r.day,r.id pair_id,EXISTS(SELECT 1 FROM likes l WHERE l.sender=? AND l.recipient=u.id AND l.active=1) liked,EXISTS(SELECT 1 FROM likes l WHERE l.sender=? AND l.recipient=u.id AND l.active=1) AND EXISTS(SELECT 1 FROM likes l WHERE l.sender=u.id AND l.recipient=? AND l.active=1) mutual FROM recommendation_pairs r JOIN users u ON u.id=CASE WHEN r.a=? THEN r.b ELSE r.a END JOIN users self ON self.id=? WHERE (r.a=? OR r.b=?) AND r.day=? AND CASE WHEN r.a=? THEN r.a_dismissed ELSE r.b_dismissed END=0 AND u.consent=1 AND self.consent=1 ORDER BY r.score DESC,r.id`).bind(id,id,id,id,id,id,id,day,id).all();
 return rows.results.map(r=>({...publicProfile(r,day),pairId:r.pair_id,score:r.score,reasons:JSON.parse(r.reasons),day:r.day,liked:!!r.liked,mutual:!!r.mutual}));
}
export async function setLike(db,id,target,active,now){
 if(typeof target!=='string'||target===id)throw new Error('INVALID_LIKE');
 if(active)await db.prepare('INSERT INTO likes(sender,recipient,active,created_at) VALUES(?,?,1,?) ON CONFLICT(sender,recipient) DO UPDATE SET active=1').bind(id,target,now).run();
 else await db.prepare('UPDATE likes SET active=0 WHERE sender=? AND recipient=?').bind(id,target).run();
 return {ok:true,active};
}
export async function dismiss(db,id,pairId){const result=await db.prepare('UPDATE recommendation_pairs SET a_dismissed=CASE WHEN a=? THEN 1 ELSE a_dismissed END,b_dismissed=CASE WHEN b=? THEN 1 ELSE b_dismissed END WHERE id=? AND (a=? OR b=?)').bind(id,id,pairId,id,id).run();if(!result.meta.changes)throw Error('NOT_FOUND');return {ok:true}}
function compatible(a,b,day){const aa=ageOn(a.birth_date,day),ba=ageOn(b.birth_date,day);return aa>=18&&ba>=18&&ba>=a.min_age&&ba<=a.max_age&&aa>=b.min_age&&aa<=b.max_age&&(a.seeking==='any'||a.seeking===b.gender)&&(b.seeking==='any'||b.seeking===a.gender)}
function hash(text){let n=2166136261;for(const c of text){n^=c.charCodeAt(0);n=Math.imul(n,16777619)}return n>>>0}
export async function runMatching(db,{now=Math.floor(Date.now()/1000),clock=()=>Math.floor(Date.now()/1000),minScore=60,maxPairs=500}={}){
 const owner=crypto.randomUUID();await db.prepare('INSERT INTO engine(id,lease_until,last_run) VALUES(1,0,0) ON CONFLICT(id) DO NOTHING').run();
 const lock=await db.prepare(`UPDATE engine SET owner=?,lease_until=? WHERE id=1 AND lease_until<=? AND (last_run<=? OR date(last_run,'unixepoch','+8 hours')<>?)`).bind(owner,now+90,now,now-15,shanghaiDay(now)).run();if(!lock.meta.changes)return {busy:true,created:0};
 let created=0;
 try{
 const day=shanghaiDay(now);const {results:users}=await db.prepare(`SELECT u.*,COALESCE(c.n,0) used FROM users u LEFT JOIN (SELECT id,count(*) n FROM (SELECT a id FROM recommendation_pairs WHERE day=? UNION ALL SELECT b id FROM recommendation_pairs WHERE day=?) GROUP BY id)c ON c.id=u.id WHERE u.consent=1 AND u.chart IS NOT NULL`).bind(day,day).all();
 const eligible=users.filter(u=>u.used<20);for(const u of eligible){u.parsed=JSON.parse(u.chart);u.tags=JSON.parse(u.interests);u.order=hash(day+u.id)}
 const previous=await db.prepare('SELECT a,b FROM recommendation_pairs').all();const seen=new Set(previous.results.map(r=>r.a+'|'+r.b));const exhausted=new Set();
 while(created<maxPairs){
 const stamp=clock();if(shanghaiDay(stamp)!==day)break;
 const available=eligible.filter(u=>u.used<20&&!exhausted.has(u.id)).sort((a,b)=>a.used-b.used||a.order-b.order);const a=available[0];if(!a)break;
 let best=null;for(const b of eligible){if(a.id===b.id||b.used>=20||!compatible(a,b,day))continue;const key=[a.id,b.id].sort().join('|');if(seen.has(key))continue;const score=Bazi.match(a.parsed,b.parsed);if(score.score===null||score.score<minScore)continue;const shared=a.tags.filter(t=>b.tags.includes(t)).length;const candidate={b,key,score,shared};if(!best||score.score>best.score.score||(score.score===best.score.score&&(b.used<best.b.used||(b.used===best.b.used&&(shared>best.shared||(shared===best.shared&&b.order<best.b.order))))))best=candidate}
 if(!best){exhausted.add(a.id);continue}const b=best.b;const [left,right]=a.id<b.id?[a,b]:[b,a];
 // Only relation descriptions are delivered. Full birth dates/times and charts remain private.
 const reasons=best.score.parts.map(p=>({name:p.name,value:p.value,max:p.max,detail:p.name==='双方字面五行覆盖'?p.detail:p.detail.split('：')[1]}));
 const deliveryTime=clock();if(shanghaiDay(deliveryTime)!==day)break;
 try{await db.prepare('INSERT INTO recommendation_pairs(id,day,a,b,a_version,b_version,score,reasons,created_at) VALUES(?,?,?,?,?,?,?,?,?)').bind(crypto.randomUUID(),day,left.id,right.id,left.version,right.version,best.score.score,JSON.stringify(reasons),deliveryTime).run();a.used++;b.used++;created++}catch(e){if(!/DAILY_RECOMMENDATION_LIMIT|PROFILE_CHANGED|UNIQUE/.test(e.message))throw e;exhausted.add(a.id);exhausted.add(b.id)}seen.add(best.key);
 if(created>0&&created%50===0){const renewed=await db.prepare('UPDATE engine SET lease_until=? WHERE id=1 AND owner=?').bind(clock()+90,owner).run();if(!renewed.meta.changes)break}
 }
 return {created,day,considered:users.length};
 }finally{await db.prepare('UPDATE engine SET lease_until=0,last_run=? WHERE id=1 AND owner=?').bind(now,owner).run()}
}
