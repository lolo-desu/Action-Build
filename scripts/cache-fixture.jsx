import React from 'react';
import {createRoot} from 'react-dom/client';
import {QueryClient,QueryClientProvider,useInfiniteQuery,useQuery} from '@tanstack/react-query';
export const client=new QueryClient({defaultOptions:{queries:{staleTime:30000,refetchOnWindowFocus:false,retry:false}}});
client.setQueryData(['me'],{id:'self'});
const headers={'Accept':'application/json','X-Content-Mode':'sfw','Accept-Language':'zh'};
const get=url=>fetch('/api/v1'+url,{credentials:'include',headers}).then(r=>{if(!r.ok)throw Error('network');return r.json()});
export const bus={status:'closed',handlers:new Map(),resume(){},on(type,fn){const set=this.handlers.get(type)||new Set();set.add(fn);this.handlers.set(type,set);return()=>set.delete(fn)},emit(type,data){for(const fn of this.handlers.get(type)||[])fn(data)}};
window.fixtureClient=client;window.fixtureBoots=(window.fixtureBoots||0)+1;
function Chat({id}){
 const detail=useQuery({queryKey:['m','sfw','zh','matches','detail',id],queryFn:()=>get('/matches/'+id)});
 const [messages,setMessages]=React.useState([]),[loading,setLoading]=React.useState(true);
 React.useEffect(()=>{let alive=true;setLoading(true);get('/matches/'+id+'/messages?limit=50').then(v=>{if(alive){setMessages(v.items);setLoading(false)}}).catch(()=>{if(alive)setLoading(false)});return()=>{alive=false}},[id]);
 React.useEffect(()=>bus.on('message.new',m=>{if(m.matchId===id)setMessages(old=>{const map=new Map(old.map(v=>[v.id,v]));map.set(m.id,m);return [...map.values()]})}),[id]);
 return <main id="main"><section className="card"><header>{detail.data?.user.displayName||'载入资料'}</header><div className="messages">{loading?'载入消息':messages.map(m=><p key={m.id} data-id={m.id}>{m.recalled?'已撤回':m.text}</p>)}</div><textarea placeholder="消息"/><button onClick={()=>window.fixtureOpen('/u/peer')}>资料</button></section></main>;
}
function List(){
 const [state,setState]=React.useState('active');
 const query=useInfiniteQuery({queryKey:['m','sfw','zh','matches',state],queryFn:({pageParam})=>get('/matches?state='+state+(pageParam?'&cursor='+pageParam:'')),initialPageParam:null,getNextPageParam:v=>v.nextCursor});
 return <main id="main"><button className="active-tab" onClick={()=>setState('active')}>进行中</button><button className="closed-tab" onClick={()=>setState('unmatched')}>已结束</button><ul>{query.data?.pages.flatMap(p=>p.items).map(m=><li key={m.id}><a href={'/matches/'+m.id} onClick={e=>{e.preventDefault();window.fixtureOpen('/matches/'+m.id)}}>{m.user.displayName}<span className="preview">{m.lastMessage?.text}</span><span className="unread">{m.unreadCount}</span></a></li>)}</ul><button className="more" onClick={()=>query.fetchNextPage()}>更多</button></main>;
}
function App(){const[path,setPath]=React.useState(location.pathname);window.fixtureOpen=path=>{history.pushState({idx:(history.state?.idx||0)+1,key:Math.random().toString(36)},'',path);setPath(path)};React.useEffect(()=>{const fn=()=>setPath(location.pathname);addEventListener('popstate',fn);return()=>removeEventListener('popstate',fn)},[]);const match=path.match(/^\/matches\/([^/]+)$/);return <><header className="app-top">测试顶栏</header>{match?<Chat id={match[1]}/>:path==='/matches'?<List/>:<main id="main">资料测试</main>}</>}
history.replaceState({idx:0,key:'root'},'',location.href);
createRoot(document.getElementById('root')).render(<QueryClientProvider client={client}><App/></QueryClientProvider>);
get('/me');
