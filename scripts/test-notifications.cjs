const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(origin='https://erp.sex') {
 const messages=[],requests=[],timers=new Map();let timerID=0;
 class Socket extends EventTarget { static OPEN=1; constructor(url){super();this.url=url;this.readyState=1} incoming(value){this.dispatchEvent(new MessageEvent('message',{data:JSON.stringify(value)}))} }
 const document=new EventTarget();document.hidden=false;
 const location={origin,host:new URL(origin).host,href:origin+'/matches',pathname:'/matches'};
 const server={me:{id:'self'},counters:{unreadMessages:3},matches:{items:[{id:'thread',user:{displayName:'测试联系人'},unreadCount:3,lastMessage:{id:'old',senderId:'peer',type:'text',text:'old preview',createdAt:'2020-01-01T00:00:00Z'}}]}};
 const window=new EventTarget();window.top=window;window.WebSocket=Socket;window.webkit={messageHandlers:{erpNativeNotifications:{postMessage:v=>messages.push(v)}}};
 window.fetch=(url,options)=>{requests.push([String(url),options]);let body=String(url).includes('/me/counters')?server.counters:String(url).includes('/matches')?server.matches:server.me;window.lastPromise=Promise.resolve(new Response(JSON.stringify(body),{status:200}));return window.lastPromise};
 const context={window,document,location,navigator:{onLine:true,language:'zh',userAgent:'fixture'},URL,Request,Response,Headers,MessageEvent,Reflect,Proxy,Number,JSON,Date,Set,Map,Array,Math,AbortController,
 setTimeout:(fn,delay)=>{const id=++timerID;timers.set(id,{fn,delay});return id},clearTimeout:id=>timers.delete(id)};
 vm.runInNewContext(fs.readFileSync(__dirname+'/../ERPStable/notifications.js','utf8'),context);
 async function run(delay){const list=[...timers].filter(([,t])=>t.delay===delay);for(const[id,t]of list){if(timers.delete(id))await t.fn()}await tick()}
 return {...context,messages,requests,timers,server,run,Socket};
}
(async()=>{
 const f=fixture();const p=f.window.fetch('/api/v1/me');assert.equal(p,f.window.lastPromise);await p;await tick();
 await f.run(0);assert(!f.messages.some(m=>m.kind==='chatMessage'||m.kind==='genericMessage'),'launch notified old messages');
 assert(f.messages.some(m=>m.kind==='session'&&m.userId==='self'));
 assert([...f.timers.values()].some(t=>t.delay===5000),'chat list is not on five-second cadence');
 const socket=new f.window.WebSocket('wss://erp.sex/api/v1/ws');let invalidations=0;socket.addEventListener('message',e=>{if(JSON.parse(e.data).type==='match.updated')invalidations++});
 socket.incoming({type:'message.new',data:{id:'incoming',matchId:'thread',senderId:'peer',type:'text',text:'新消息预览'}});
 socket.incoming({type:'message.new',data:{id:'incoming',matchId:'thread',senderId:'peer',type:'text',text:'duplicate'}});
 await f.run(0);assert(invalidations>0,'real-time list invalidation missing');
 const alerts=()=>f.messages.filter(m=>m.kind==='chatMessage');assert.equal(alerts().length,1);assert.equal(alerts()[0].title,'测试联系人');assert.equal(alerts()[0].body,'新消息预览');assert.equal(alerts()[0].matchId,'thread');
 socket.incoming({type:'counters',data:{unreadMessages:4}});assert(![...f.timers.values()].some(t=>t.delay===2200),'counter duplicated a message notification');
 socket.incoming({type:'message.new',data:{id:'outgoing',matchId:'thread',senderId:'self',type:'text',text:'own'}});assert.equal(alerts().length,1);
 f.location.pathname='/matches/thread';socket.incoming({type:'message.new',data:{id:'reading',matchId:'thread',senderId:'peer',type:'text',text:'reading'}});assert.equal(alerts().length,1,'currently open chat alerted');
 f.window.__vrcrpAppActive(false);socket.incoming({type:'message.new',data:{id:'inactive',matchId:'thread',senderId:'peer',type:'image'}});assert.equal(alerts().at(-1).body,'[图片]');await f.run(0);assert.equal(f.timers.size,0,'inactive polling continued');
 f.window.__vrcrpAppActive(true);f.location.pathname='/posts';await f.run(0);assert([...f.timers.values()].some(t=>t.delay===15000));
 f.server.matches.items[0].lastMessage={id:'poll-new',senderId:'peer',type:'voice',createdAt:new Date().toISOString()};f.server.matches.items[0].unreadCount=4;await f.run(15000);assert.equal(alerts().at(-1).body,'[语音]','polling missed a new latest message');
 const before=alerts().length;await f.run(15000);assert.equal(alerts().length,before,'poll repeated a message');
 const foreign=new f.window.WebSocket('wss://example.org/api/v1/ws');foreign.incoming({type:'message.new',data:{id:'foreign',matchId:'thread',senderId:'peer',text:'foreign'}});assert.equal(alerts().length,before);
 f.server.me={id:'other-account'};await f.window.fetch('/api/v1/me');await tick();assert.equal(f.messages.filter(m=>m.kind==='session').at(-1).userId,'other-account');
 socket.incoming({type:'message.new',data:{id:'late-other-user',matchId:'thread',senderId:'peer',type:'text',text:'stale'}});assert.equal(alerts().length,before,'previous account socket leaked a notification');
 f.server.me={};await f.window.fetch('/api/v1/me');await tick();assert.equal(f.timers.size,0,'logout left polling active');
 assert.equal(fixture('https://example.org').window.WebSocket.name,'Socket');
 console.log('PASS: old-message baseline, previews and media, sender/current-chat exclusion, deduplication, live list updates, 5/15-second polling, resume, logout/account isolation and original fetch promises');
})().catch(error=>{console.error(error);process.exitCode=1});
