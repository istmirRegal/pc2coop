"""Browser UI for the local co-op controller (served on 127.0.0.1 only)."""

HTML = r"""<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>PC2 Co-op</title>
<style>
:root{--bg:#121a22;--panel:#1b2631;--line:#2c3b49;--text:#e6eef5;--muted:#9fb3c4;--accent:#7ee0b8;--warn:#ffcf70;--bad:#ff8f8f}
*{box-sizing:border-box}body{margin:0;font:15px/1.45 system-ui,Segoe UI,sans-serif;background:var(--bg);color:var(--text)}
header{display:flex;gap:16px;align-items:center;padding:14px 20px;border-bottom:1px solid var(--line)}
header h1{font-size:18px;margin:0}#status{color:var(--muted)}
main{display:grid;grid-template-columns:minmax(300px,380px) 1fr;gap:16px;padding:16px 20px}
@media (max-width:900px){main{grid-template-columns:1fr}}
section{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px;margin-bottom:16px}
h2{font-size:14px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);margin:0 0 10px}
input{background:#0e151c;border:1px solid var(--line);color:var(--text);padding:8px;border-radius:6px;width:100%;margin:4px 0}
button{background:var(--accent);color:#0b1a14;border:0;padding:8px 12px;border-radius:6px;font-weight:600;cursor:pointer}
button.secondary{background:#344656;color:var(--text)}button:disabled{opacity:.45;cursor:default}
.row{display:flex;gap:8px;align-items:center}.row>*{flex:1}
.player{display:flex;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid var(--line)}
.dot{width:12px;height:12px;border-radius:50%;flex:none}.grow{flex:1}.muted{color:var(--muted);font-size:13px}
#map{width:100%;aspect-ratio:1/1;background:#0b1117;border-radius:8px;display:block}
table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:6px;border-bottom:1px solid var(--line)}
#feed div{padding:4px 0;border-bottom:1px solid var(--line);font-size:14px}
.warn{color:var(--warn)}.bad{color:var(--bad)}code{background:#0e151c;padding:2px 6px;border-radius:4px;word-break:break-all}
</style></head><body>
<header><h1>Planet Coaster 2 · Live Co-op</h1><span id="status">lädt …</span></header>
<main><div>
<section id="connect"><h2>Sitzung</h2>
<label>Dein Name<input id="name" maxlength="32" value="Spieler"></label>
<label>Sitzungsname (zum Fortsetzen, optional)<input id="session" maxlength="40" placeholder="z. B. Freizeitpark"></label>
<button id="host">Raum hosten</button>
<hr style="border-color:var(--line)">
<label>Adresse des Hosts<input id="address" placeholder="100.64.0.5:28763"></label>
<label>Raumschlüssel<input id="key"></label>
<button id="join" class="secondary">Beitreten</button></section>
<section id="room" hidden><h2>Raum</h2><div id="roominfo"></div>
<p class="muted">Alle starten denselben Park: einen neuen Sandbox-Park mit gleichen Einstellungen oder dieselbe Parkdatei.</p>
<button id="leave" class="secondary">Sitzung verlassen</button></section>
<section><h2>Spieler</h2><div id="players" class="muted">Noch nicht verbunden.</div></section>
<section><h2>Hinweise</h2><div id="warnings" class="muted">–</div></section>
</div><div>
<section><h2>Karte</h2><canvas id="map" width="800" height="800"></canvas>
<p class="muted">Punkte: Objekte in der Farbe ihres Erbauers. Pfeile: Spieler und ihre Blickrichtung.</p></section>
<section><h2>Wer hat was gebaut</h2><table><thead><tr><th>Spieler</th><th>Platziert</th><th>Bearbeitet</th><th>Gelöscht</th></tr></thead><tbody id="stats"></tbody></table></section>
<section><h2>Verlauf</h2><div id="feed" class="muted">–</div></section>
</div></main>
<script>
const TOKEN="__TOKEN__";const $=id=>document.getElementById(id);let state={};
try{$('name').value=localStorage.getItem('pc2coop-name')||'Spieler';$('address').value=localStorage.getItem('pc2coop-address')||''}catch(e){}
async function post(action,data){try{localStorage.setItem('pc2coop-name',$('name').value);localStorage.setItem('pc2coop-address',$('address').value)}catch(e){}
 const r=await fetch('/api/'+action,{method:'POST',headers:{'Content-Type':'application/json','X-PC2-Token':TOKEN},body:JSON.stringify(data||{})});
 const j=await r.json();if(j.error)alert(j.error);refresh()}
$('host').onclick=()=>post('host',{name:$('name').value,session:$('session').value});
$('join').onclick=()=>post('join',{name:$('name').value,address:$('address').value,key:$('key').value});
$('leave').onclick=()=>post('leave');
function el(tag,text,cls){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e}
const ACT={baut:'baut gerade',schaut:'schaut sich um',empfaengt:'übernimmt Änderungen'};
function render(){const s=state,room=s.room||{};
 $('status').textContent='Spiel: '+(s.game&&s.game.pid?(s.game.ready?'Park bereit':'läuft, kein Park geladen'):'nicht gefunden')+(s.connected?' · verbunden':' · getrennt')+(s.game&&s.game.pending?' · '+s.game.pending+' Änderungen ausstehend':'');
 $('connect').hidden=!!s.connected;$('room').hidden=!s.connected;
 const info=$('roominfo');info.replaceChildren();
 if(s.hosting){info.append(el('div','Raumschlüssel (nur an Freunde geben):'),el('code',s.key),el('div','Adressen: '+((s.addresses||[]).map(a=>a+':'+s.port).join(', ')||'–'),'muted'))}
 else if(s.connected){info.append(el('div','Verbunden als '+(s.peer||'?')))}
 const players=$('players');players.replaceChildren();
 (room.players||[]).forEach(p=>{const row=el('div',undefined,'player');const d=el('span',undefined,'dot');d.style.background=p.color;
  const body=el('div',undefined,'grow');body.append(el('div',p.name+(p.peer===s.peer?' (du)':'')));
  const pr=p.pres;body.append(el('div',pr?(ACT[pr.act]||pr.act)+' · '+pr.mode+' · '+pr.p.map(v=>Math.round(v)).join(', '):'noch kein Park geladen','muted'));
  const b=el('button','Hinspringen','secondary');b.disabled=!pr||p.peer===s.peer;b.onclick=()=>post('jump',{peer:p.peer});
  row.append(d,body,b);players.append(row)});
 if(!(room.players||[]).length)players.textContent='Noch nicht verbunden.';
 const w=[...(s.warnings||[])];if(s.error)w.unshift(s.error);if(room.baseline_mismatch)w.unshift('Achtung: Die Parks der Spieler unterscheiden sich. Alle müssen denselben Startpark laden.');
 if(room.conflicts)w.push(room.conflicts+' gleichzeitige Bearbeitungen wurden aufgelöst.');
 $('warnings').replaceChildren(...(w.length?w.map(t=>el('div',t,'warn')):[el('div','Alles in Ordnung.')]));
 const stats=$('stats');stats.replaceChildren();Object.entries(room.stats||{}).forEach(([n,v])=>{const tr=el('tr');[n,v.created,v.edited,v.deleted].forEach(x=>tr.append(el('td',String(x))));stats.append(tr)});
 $('feed').replaceChildren(...(room.feed||[]).slice().reverse().map(f=>el('div',new Date(f.t*1000).toLocaleTimeString()+' – '+f.text)));
 draw(room)}
function draw(room){const c=$('map'),g=c.getContext('2d');g.clearRect(0,0,c.width,c.height);
 const pts=[];(room.objects||[]).forEach(o=>pts.push(o.p));(room.players||[]).forEach(p=>p.pres&&pts.push(p.pres.p));
 if(!pts.length){g.fillStyle='#5d7286';g.font='24px system-ui';g.fillText('Noch keine Daten',300,400);return}
 let minx=Math.min(...pts.map(p=>p[0])),maxx=Math.max(...pts.map(p=>p[0])),minz=Math.min(...pts.map(p=>p[2])),maxz=Math.max(...pts.map(p=>p[2]));
 const span=Math.max(maxx-minx,maxz-minz,60)*1.2,cx=(minx+maxx)/2,cz=(minz+maxz)/2,sc=c.width/span;
 const X=x=>c.width/2+(x-cx)*sc,Y=z=>c.height/2+(z-cz)*sc;
 const color={};(room.players||[]).forEach(p=>color[p.name]=p.color);
 (room.objects||[]).forEach(o=>{g.fillStyle=color[o.creator]||'#8899aa';g.beginPath();g.arc(X(o.p[0]),Y(o.p[2]),4,0,7);g.fill()});
 (room.players||[]).forEach(p=>{if(!p.pres)return;const x=X(p.pres.p[0]),y=Y(p.pres.p[2]),a=p.pres.ypr[0];
  g.strokeStyle=g.fillStyle=p.color;g.lineWidth=3;g.beginPath();g.arc(x,y,9,0,7);g.fill();
  g.beginPath();g.moveTo(x,y);g.lineTo(x+Math.sin(a)*28,y+Math.cos(a)*28);g.stroke();
  g.font='bold 20px system-ui';g.fillText(p.name,x+12,y-12)})}
async function refresh(){try{state=await (await fetch('/api/state')).json();render()}catch(e){$('status').textContent='Controller nicht erreichbar.'}}
setInterval(refresh,700);refresh();
</script></body></html>"""
