/* Calendar: lunar-javascript 1.7.7 (MIT). Scores below are this prototype's own entertainment heuristic. */
(function(root){
  const api=typeof module==='object'&&module.exports?require('./vendor/lunar.js'):root;
  const W=['木','火','土','金','水'],stems={甲:'木',乙:'木',丙:'火',丁:'火',戊:'土',己:'土',庚:'金',辛:'金',壬:'水',癸:'水'},branches={子:'水',丑:'土',寅:'木',卯:'木',辰:'土',巳:'火',午:'火',未:'土',申:'金',酉:'金',戌:'土',亥:'水'};
  const combine=['子丑','寅亥','卯戌','辰酉','巳申','午未'],clash=['子午','丑未','寅申','卯酉','辰戌','巳亥'];
  function chart(birth){
    if(!birth||!/^\d{4}-\d{2}-\d{2}$/.test(birth.date))throw Error('请填写有效的公历出生日期');
    const [y,m,d]=birth.date.split('-').map(Number),check=new Date(Date.UTC(y,m-1,d));
    if(y<1900||y>2100||check.getUTCFullYear()!==y||check.getUTCMonth()!==m-1||check.getUTCDate()!==d)throw Error('出生日期无效');
    const known=!birth.unknown;
    if(known&&!/^([01]\d|2[0-3]):[0-5]\d$/.test(birth.time||''))throw Error('请填写有效的出生时间');
    const make=(h,n,s=0)=>{const e=api.Solar.fromYmdHms(y,m,d,h,n,s).getLunar().getEightChar();e.setSect(2);return e};
    const [h,n]=(known?birth.time:'12:00').split(':').map(Number),e=make(h,n);
    const pillars=[e.getYear(),e.getMonth(),e.getDay(),known?e.getTime():null];let uncertain=false;
    if(!known){const a=make(0,0),b=make(23,59,59);if(a.getYear()!==b.getYear()){pillars[0]=null;uncertain=true}if(a.getMonth()!==b.getMonth()){pillars[1]=null;uncertain=true}}
    const counts=Object.fromEntries(W.map(x=>[x,0]));for(const p of pillars)if(p){counts[stems[p[0]]]++;counts[branches[p[1]]]++}
    return {pillars,counts,complete:known,uncertain,dayStem:e.getDayGan(),dayBranch:e.getDayZhi(),dayElement:stems[e.getDayGan()]};
  }
  function match(a,b){
    if(!a.complete||!b.complete)return {score:null,parts:[],label:'待补充时辰'};
    const x=a.dayElement,y=b.dayElement,gen=(W.indexOf(x)+1)%5===W.indexOf(y)||(W.indexOf(y)+1)%5===W.indexOf(x);
    let stemScore=x===y?22:gen?30:12,stemRelation=x===y?'五行相同':gen?'五行相生':'五行相克';
    const pair=a.dayBranch+b.dayBranch,rev=b.dayBranch+a.dayBranch;
    const isCombine=combine.includes(pair)||combine.includes(rev),isClash=clash.includes(pair)||clash.includes(rev);
    let branchScore=isCombine?30:isClash?10:a.dayBranch===b.dayBranch?22:18;
    let branchRelation=isCombine?'六合':isClash?'六冲':a.dayBranch===b.dayBranch?'同支':'未列入六合或六冲';
    const cover=W.filter(w=>a.counts[w]+b.counts[w]>0),coverScore=cover.length*8;
    return {score:stemScore+branchScore+coverScore,label:'合缘参考',parts:[{name:'日干五行关系',value:stemScore,max:30,detail:`${a.dayStem}${x} · ${b.dayStem}${y}：${stemRelation}`},{name:'日支传统关系',value:branchScore,max:30,detail:`${a.dayBranch} · ${b.dayBranch}：${branchRelation}`},{name:'双方字面五行覆盖',value:coverScore,max:40,detail:`四柱天干与地支本气共出现 ${cover.length} 种五行：${cover.join('、')}`}]};
  }
  const result={chart,match,elements:W,stemElements:stems,branchElements:branches};if(typeof module==='object'&&module.exports)module.exports=result;else root.Bazi=result;
})(typeof window==='undefined'?globalThis:window);
