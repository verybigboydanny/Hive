/* Hive website: routing, animations, hive canvas, handoff demo.
   Requires GSAP + ScrollTrigger (loaded from cdnjs in index.html). */
(function(){
var $=function(s){return document.querySelector(s)},$$=function(s){return Array.prototype.slice.call(document.querySelectorAll(s))};
var pages=['home','how','docs','downloads','releases','troubleshooting','brand'],G=window.gsap,calm=matchMedia('(prefers-reduced-motion: reduce)').matches,ST=window.ScrollTrigger,tl,cur=null;
if(G&&ST)G.registerPlugin(ST);
var nv=$('#nv'),mb=$('#mb');mb.onclick=function(){var o=nv.classList.toggle('o');mb.setAttribute('aria-expanded',o)};
function dash(e,n){var l=n||e.getTotalLength();e.style.strokeDasharray=l;e.style.strokeDashoffset=l}
function hero(){
 if(!G||calm)return;
 tl=G.timeline({defaults:{ease:'power3.out'}});
 tl.from('.pill',{y:12,opacity:0,duration:.6}).from('.l1',{y:50,opacity:0,duration:1},'-=.3').from('.l2',{clipPath:'inset(-20% 100% -20% 0)',duration:1.3,ease:'power2.inOut'},'-=.5').from('.hero2 p.s,.hero2 .cta',{y:16,opacity:0,duration:.7,stagger:.1},'-=.6').from('.hvw',{y:70,opacity:0,duration:1.1},'-=.6');
}
var hv=$('#hv'),X=hv.getContext('2d'),HW,HH,HR,HC=[],HA=[],HK,RP=[],PX=-999,PY=-999,HT=0,HL=0,HRAF=0,LG=new Image(),CLR=[[240,135,106],[79,209,161],[111,168,255]],NMS=['Claude','GPT','Gemini'];
LG.src='data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22%3E%3Cdefs%3E%3ClinearGradient id=%22g0%22 x1=%220%22 y1=%220%22 x2=%220%22 y2=%221%22%3E%3Cstop offset=%220%22 stop-color=%22%23FFE394%22/%3E%3Cstop offset=%221%22 stop-color=%22%23F8BC2E%22/%3E%3C/linearGradient%3E%3ClinearGradient id=%22g1%22 x1=%220%22 y1=%220%22 x2=%220%22 y2=%221%22%3E%3Cstop offset=%220%22 stop-color=%22%23F7B724%22/%3E%3Cstop offset=%221%22 stop-color=%22%23D98C00%22/%3E%3C/linearGradient%3E%3ClinearGradient id=%22g2%22 x1=%220%22 y1=%220%22 x2=%220%22 y2=%221%22%3E%3Cstop offset=%220%22 stop-color=%22%23EBA10B%22/%3E%3Cstop offset=%221%22 stop-color=%22%23B86E00%22/%3E%3C/linearGradient%3E%3C/defs%3E%3Cpolygon points=%2269.5%2C19.0 69.5%2C41.4 50.0%2C52.7 30.5%2C41.4 30.5%2C18.9 50.0%2C7.7%22 fill=%22url%28%23g0%29%22 stroke=%22url%28%23g0%29%22 stroke-width=%223%22 stroke-linejoin=%22round%22/%3E%3Cpolygon points=%2292.3%2C58.5 92.3%2C81.0 72.8%2C92.2 53.3%2C81.0 53.3%2C58.5 72.8%2C47.2%22 fill=%22url%28%23g1%29%22 stroke=%22url%28%23g1%29%22 stroke-width=%223%22 stroke-linejoin=%22round%22/%3E%3Cpolygon points=%2246.7%2C58.5 46.7%2C81.0 27.2%2C92.2 7.7%2C81.0 7.7%2C58.5 27.2%2C47.2%22 fill=%22url%28%23g2%29%22 stroke=%22url%28%23g2%29%22 stroke-width=%223%22 stroke-linejoin=%22round%22/%3E%3C/svg%3E';X.lineJoin='round';var AC=[245,178,26],HUE=0,DP=1,BL=document.createElement('canvas'),LGC=document.createElement('canvas');LG.onload=mkLogo;
function mkLogo(){if(!LG.naturalWidth||!HR)return;var s=Math.ceil(HR*2.2*DP);LGC.width=LGC.height=s;var c=LGC.getContext('2d');if('filter' in c)c.filter='hue-rotate('+HUE+'deg)';c.drawImage(LG,0,0,s,s)}
function hsize(){var w=Math.min(1180,innerWidth-48),cols=w<600?8:w<900?12:17,dpr=Math.min(1.75,devicePixelRatio||1);DP=dpr;HW=w;HR=w/(cols+.5)/1.732;HH=Math.round(w<600?380:w*.42);hv.width=HW*dpr;hv.height=HH*dpr;hv.style.width=HW+'px';hv.style.height=HH+'px';X.setTransform(dpr,0,0,dpr,0,0);
 HC=[];var dx=HR*1.732,rows=Math.ceil(HH/(1.5*HR))+1,best=1e9;
 for(var r=0;r<rows;r++)for(var c=0;c<cols+1;c++){var x=(c+.5+(r%2)*.5)*dx,y=r*1.5*HR+HR;if(x-dx/2>=HW)continue;HC.push({x:x,y:y,h:[0,0,0],m:0,rp:0,sp:0})}
 HC.forEach(function(c){var d=Math.hypot(c.x-HW/2,c.y-HH/2);if(d<best){best=d;HK=c}});
 HA=[0,1,2].map(function(){return{x:HW/2,y:HH/2,tr:[],tg:null,u:0}});
 BL.width=hv.width;BL.height=hv.height;var B=BL.getContext('2d'),q2=HR-1.5;B.setTransform(DP,0,0,DP,0,0);B.lineJoin='round';B.lineWidth=1.2;
 HC.forEach(function(c){hpath(c.x,c.y,q2,B);B.fillStyle='#0f0f11';B.fill();B.strokeStyle='rgba(0,0,0,.65)';B.stroke();B.beginPath();for(var k=3;k<=6;k++){var an=(60*(k%6)-30)*Math.PI/180;B[k===3?'moveTo':'lineTo'](c.x+q2*Math.cos(an),c.y+q2*Math.sin(an))}B.strokeStyle='rgba(255,255,255,.07)';B.stroke()});mkLogo()}
function nat(i,t){var f=[[.29,.43],[.23,.37],[.33,.27]][i],p=i*2.1;return{x:HW/2+Math.sin(t*f[0]+p)*HW*.4*Math.cos(t*.09+i),y:HH/2+Math.sin(t*f[1]+p*1.3)*HH*.36}}
function hstep(t,dt){
 HA.forEach(function(a,i){var on=t<a.u,g=on?a.tg:nat(i,t),k=Math.min(1,dt*(on?4:2));a.x+=(g.x-a.x)*k;a.y+=(g.y-a.y)*k;a.tr.push({x:a.x,y:a.y});if(a.tr.length>30)a.tr.shift()});
 RP=RP.filter(function(r){return t-r.t<1.9});
 var dec=Math.pow(.4,dt),dm=Math.pow(.97,dt);
 HC.forEach(function(c){for(var i=0;i<3;i++){var d=Math.hypot(c.x-HA[i].x,c.y-HA[i].y);c.h[i]*=dec;if(d<HR*1.9){c.h[i]=Math.min(1,c.h[i]+dt*3*(1-d/(HR*1.9)));c.m=Math.min(1,c.m+dt*.12)}}
  c.m*=dm;c.rp=0;RP.forEach(function(r){var d=Math.hypot(c.x-r.x,c.y-r.y),k=1-Math.abs(d-(t-r.t)*HR*9)/(HR*1.5);if(k>0)c.rp=Math.max(c.rp,k*(1-(t-r.t)/1.9))});
  c.sp=Math.pow(Math.max(0,1-Math.hypot(c.x-PX,c.y-PY)/(HR*5)),2)})}
function hpath(x,y,r,c){c=c||X;c.beginPath();for(var k=0;k<6;k++){var a=(60*k-30)*Math.PI/180;c[k?'lineTo':'moveTo'](x+r*Math.cos(a),y+r*Math.sin(a))}c.closePath()}
function hdraw(t){
 X.clearRect(0,0,HW,HH);X.drawImage(BL,0,0,HW,HH);var r2=HR-1.5;
 for(var n=0;n<HC.length;n++){var c=HC[n],tot=c.h[0]+c.h[1]+c.h[2],am=c.rp+c.sp,a=Math.min(1,tot+am);
  if(a>.02){var w=tot+am||1,rr=AC[0]*am,gg=AC[1]*am,bb=AC[2]*am;for(var i=0;i<3;i++){rr+=CLR[i][0]*c.h[i];gg+=CLR[i][1]*c.h[i];bb+=CLR[i][2]*c.h[i]}rr=rr/w|0;gg=gg/w|0;bb=bb/w|0;
   var gr=X.createRadialGradient(c.x,c.y,0,c.x,c.y,HR);gr.addColorStop(0,'rgba('+rr+','+gg+','+bb+','+a*.7+')');gr.addColorStop(1,'rgba('+rr+','+gg+','+bb+','+a*.1+')');
   X.globalCompositeOperation='lighter';hpath(c.x,c.y,r2);X.fillStyle=gr;X.fill();X.globalCompositeOperation='source-over';
   hpath(c.x,c.y,r2*.62);X.strokeStyle='rgba('+rr+','+gg+','+bb+','+Math.min(1,a*.9)+')';X.lineWidth=1.2;X.stroke();X.beginPath();X.arc(c.x,c.y,1.8,0,6.3);X.fillStyle='rgba(255,255,255,'+a*.9+')';X.fill();
   X.beginPath();for(var k=3;k<=6;k++){var an=(60*(k%6)-30)*Math.PI/180;X[k===3?'moveTo':'lineTo'](c.x+r2*Math.cos(an),c.y+r2*Math.sin(an))}X.strokeStyle='rgba(255,255,255,'+a*.25+')';X.stroke()}
  if(c.m>.02){hpath(c.x,c.y,HR*.26);X.fillStyle='rgba('+AC+','+c.m*.35+')';X.fill()}}
 var u=(t%3)/3;hpath(HK.x,HK.y,HR*(1+u*5));X.strokeStyle='rgba('+AC+','+(1-u)*.35+')';X.lineWidth=1.5;X.stroke();
 if(LGC.width)X.drawImage(LGC,HK.x-HR*1.1,HK.y-HR*1.1,HR*2.2,HR*2.2);
 [[0,1],[1,2],[2,0]].forEach(function(p,j){var A=HA[p[0]],B=HA[p[1]],g=X.createLinearGradient(A.x,A.y,B.x,B.y);g.addColorStop(0,'rgba('+CLR[p[0]]+',.3)');g.addColorStop(1,'rgba('+CLR[p[1]]+',.3)');X.strokeStyle=g;X.lineWidth=1;X.beginPath();X.moveTo(A.x,A.y);X.lineTo(B.x,B.y);X.stroke();
  var v=(t*.4+j/3)%1;X.beginPath();X.arc(A.x+(B.x-A.x)*v,A.y+(B.y-A.y)*v,2.6,0,6.3);X.fillStyle='#fff';X.fill()});
 HA.forEach(function(a,i){var c=CLR[i],n=a.tr.length;X.lineCap='round';
  for(var j=2;j<n;j+=2){X.beginPath();X.moveTo(a.tr[j-2].x,a.tr[j-2].y);X.lineTo(a.tr[j].x,a.tr[j].y);X.strokeStyle='rgba('+c+','+j/n*.6+')';X.lineWidth=j/n*4;X.stroke()}
  var g=X.createRadialGradient(a.x,a.y,0,a.x,a.y,HR*1.7);g.addColorStop(0,'rgba('+c+',.55)');g.addColorStop(1,'rgba('+c+',0)');X.globalCompositeOperation='lighter';X.fillStyle=g;X.beginPath();X.arc(a.x,a.y,HR*1.7,0,6.3);X.fill();X.globalCompositeOperation='source-over';
  X.beginPath();X.arc(a.x,a.y,HR*.32,0,6.3);X.fillStyle='rgb('+c+')';X.fill();X.beginPath();X.arc(a.x,a.y,HR*.12,0,6.3);X.fillStyle='#fff';X.fill();
  X.font='500 11px "JetBrains Mono",monospace';X.fillStyle='rgba(255,255,255,.85)';X.fillText(NMS[i],a.x+HR*.55,a.y-HR*.45)})}
function hframe(ts){HRAF=requestAnimationFrame(hframe);var t=ts/1000,dt=Math.min(.05,Math.max(0,t-HL));HL=t;HT=t;hstep(t,dt);hdraw(t)}
function still(){for(var k=0;k<160;k++)hstep(k*.05,.05);hdraw(8)}
hsize();if(calm)still();
new IntersectionObserver(function(e){if(e[0].isIntersecting){if(!HRAF&&!calm){HL=performance.now()/1000;HRAF=requestAnimationFrame(hframe)}}else{cancelAnimationFrame(HRAF);HRAF=0}}).observe(hv);
var rz,lw=innerWidth;addEventListener('resize',function(){if(innerWidth===lw)return;lw=innerWidth;clearTimeout(rz);rz=setTimeout(function(){hsize();if(calm)still()},150)});
function ptr(e){var r=hv.getBoundingClientRect();PX=e.clientX-r.left;PY=e.clientY-r.top}
hv.addEventListener('pointermove',ptr);hv.addEventListener('pointerleave',function(){PX=PY=-999});
hv.addEventListener('pointerdown',function(e){ptr(e);var b=0,bd=1e9;HA.forEach(function(a,i){var d=Math.hypot(a.x-PX,a.y-PY);if(d<bd){bd=d;b=i}});HA[b].tg={x:PX,y:PY};HA[b].u=HT+2.2;RP.push({x:PX,y:PY,t:HT});if(e.pointerType==='touch')setTimeout(function(){PX=PY=-999},700)});
var stm=$('#stm');stm.innerHTML=stm.textContent.split(' ').map(function(w){return '<span>'+w+'</span>'}).join(' ');
var SS=[['Share','Every agent reads and writes the same project files.'],['Remember','Decisions are recorded once and every agent can read them.'],['Speak','Agents message each other: questions, warnings, confirmations.'],['Hand off','Work passes between agents with its full context.']],si=-1;
function step(i){if(i===si)return;si=i;$('#dg').setAttribute('data-s',i);$$('.dots li').forEach(function(d,j){d.classList.toggle('on',j<=i)});$('#sp').textContent=SS[i][1];var w=$('#sw');w.textContent=SS[i][0];if(G&&!calm)G.from(w,{clipPath:'inset(-20% 100% -20% 0)',duration:.9,ease:'power2.inOut'})}
function init(h){
 if(h==='home'){hero();step(0);si=-1;step(0);
  if(G&&ST){ST.create({trigger:'#story',start:'top top+=64',end:'bottom bottom',onUpdate:function(s){step(Math.min(3,Math.floor(s.progress*4)))}});
   if(!calm)G.fromTo('#stm span',{opacity:.15},{opacity:1,stagger:.1,ease:'none',scrollTrigger:{trigger:'#stm',start:'top 80%',end:'bottom 50%',scrub:true}})}}
 if(!G||!ST||calm)return;G.to('#sp0',{scaleX:1,ease:'none',scrollTrigger:{start:0,end:'max',scrub:.3}});var q='#'+h+' ';
 $$(q+'h2,'+q+'.ptop>*,'+q+'.fx li,'+q+'.row,'+q+'details,'+q+'.demo').forEach(function(e){G.from(e,{y:30,opacity:0,duration:.9,ease:'power3.out',scrollTrigger:{trigger:e,start:'top 90%'}})});
 $$(q+'h2 .sc').forEach(function(e){G.from(e,{clipPath:'inset(-20% 100% -20% 0)',duration:1.5,ease:'power2.inOut',delay:.2,scrollTrigger:{trigger:e,start:'top 88%'}})});
 ST.refresh();
}
function show(h){
 $$('.pg').forEach(function(p){p.hidden=p.id!==h});
 $$('nav a:not(.btn)').forEach(function(a){a.setAttribute('aria-current',a.getAttribute('href')==='#'+h?'page':'false')});
 nv.classList.remove('o');mb.setAttribute('aria-expanded','false');
 document.title=h==='home'?'Hive – Every AI agent, one hive':'Hive – '+h.charAt(0).toUpperCase()+h.slice(1);
 window.scrollTo(0,0);if(ST)ST.getAll().forEach(function(t){t.kill()});init(h);
}
function route(){var h=location.hash.slice(1);if(pages.indexOf(h)<0)h='home';
 if(cur===null||!G||calm){cur=h;show(h);return}if(h===cur)return;cur=h;
 G.timeline().set('#cv',{transformOrigin:'50% 100%'}).to('#cv',{scaleY:1,duration:.45,ease:'power3.in'}).add(function(){show(h)}).set('#cv',{transformOrigin:'50% 0%'}).to('#cv',{scaleY:0,duration:.6,ease:'power3.out'})}
var dn=$('.dn'),arts=$$('.dp');
arts.forEach(function(a,i){var b=document.createElement('button');b.textContent=a.getAttribute('data-t');b.setAttribute('role','tab');b.onclick=function(){pick(i)};dn.appendChild(b)});
function pick(i){arts.forEach(function(a,j){a.hidden=i!==j});$$('.dn button').forEach(function(b,j){b.setAttribute('aria-selected',i===j)})}pick(0);
var HX=[90,260,430],HN=['Claude','GPT','Gemini'],HO=0,hoU=0;
function giveTo(j){if(j===HO)return;var f=HO;HO=j;
 $$('#hoS .oh').forEach(function(o,k){o.setAttribute('aria-pressed',k===j)});$('#hl').textContent=HN[j]+' picked up the work from '+HN[f]+'. Same files, same memory, same tasks.';
 if(G&&!calm){G.to('#bx',{x:HX[j],duration:1,ease:'power3.inOut'});G.fromTo('#by',{y:0},{y:-70,duration:.5,yoyo:true,repeat:1,ease:'power2.out'});G.fromTo('#hh'+j,{scale:.7,opacity:1},{scale:2.4,opacity:0,duration:1,delay:.8,ease:'power2.out'})}else $('#bx').setAttribute('transform','translate('+HX[j]+' 170)')}
$$('#hoS .oh').forEach(function(o){var j=+o.dataset.j;o.onclick=function(){hoU=1;giveTo(j)};o.onkeydown=function(e){if(e.key==='Enter'||e.key===' '){e.preventDefault();hoU=1;giveTo(j)}}});
if(G&&!calm)G.to('#ctx',{rotation:360,transformOrigin:'0 0',duration:8,repeat:-1,ease:'none'});
setInterval(function(){var hm=$('#home');if(!hoU&&hm&&!hm.hidden&&!document.hidden&&!calm)giveTo((HO+1)%3)},3400);
var CX=0,CY=0,CQ=0,cg=$('#cg');var TH={ember:[[255,106,26],-24],honey:[[245,178,26],0],signal:[[46,230,197],130],rose:[[255,77,120],-57]};
function setTheme(k,f){AC=TH[k][0];HUE=TH[k][1];mkLogo();document.documentElement.setAttribute('data-a',k);$$('.th button').forEach(function(b){b.setAttribute('aria-pressed',b.dataset.t===k)});try{localStorage.setItem('hv-a2',k)}catch(e){}if(f&&HK)RP.push({x:HK.x,y:HK.y,t:HT})}
$$('.th button').forEach(function(b){b.onclick=function(){setTheme(b.dataset.t,1)}});
var sv='honey';try{sv=localStorage.getItem('hv-a2')||'honey'}catch(e){}if(!TH[sv])sv='ember';setTheme(sv);
addEventListener('pointermove',function(e){if(e.pointerType==='mouse'){CX=e.clientX;CY=e.clientY;if(!CQ){CQ=1;requestAnimationFrame(function(){CQ=0;cg.style.transform='translate3d('+CX+'px,'+CY+'px,0)'})}}});
if(G&&!calm&&matchMedia('(pointer:fine)').matches)$$('.btn').forEach(function(b){b.addEventListener('pointermove',function(e){var r=b.getBoundingClientRect();G.to(b,{x:(e.clientX-r.left-r.width/2)*.25,y:(e.clientY-r.top-r.height/2)*.35,duration:.3})});b.addEventListener('pointerleave',function(){G.to(b,{x:0,y:0,duration:.6,ease:'elastic.out(1,.4)'})})});
addEventListener('hashchange',route);route();
})();
