(() => {
  'use strict';
  if (window !== window.top || location.origin !== 'https://erp.sex') return;
  const reduce = () => document.documentElement?.dataset.vrcrpReduceMotion === 'true' || matchMedia('(prefers-reduced-motion: reduce)').matches;
  const roots = new Set(['/','/discover','/browse','/likes','/likes/sent','/matches','/posts','/me']);
  let lastPath = location.pathname, queued = false;
  let seen = new WeakSet(), initializedPane = null;
  function animate(element, frames, duration = 150) {
    if (!element || reduce() || element.getAnimations().length) return;
    element.animate(frames, { duration, easing: 'cubic-bezier(.2,.8,.2,1)' });
  }
  const compare = (a,b) => {
    if (!!a.pending !== !!b.pending) return a.pending ? 1 : -1;
    const ta = Date.parse(a.createdAt), tb = Date.parse(b.createdAt);
    return Number.isFinite(ta) && Number.isFinite(tb) && ta !== tb ? ta-tb : String(a.createdAt).localeCompare(String(b.createdAt)) || String(a.id).localeCompare(String(b.id));
  };
  function orderMessages(pane) {
    const id = location.pathname.match(/^\/matches\/([^/]+)$/)?.[1];
    if (!id || !pane) return;
    // Locate the site's existing message useState. Use its bound React setter;
    // preserve message objects, server timestamps and the original row handlers.
    const key = Object.keys(pane).find(k => k.startsWith('__reactFiber$'));
    let fiber = key && pane[key];
    for (let i=0; fiber && i<40; i++,fiber=fiber.return) {
      let hook=fiber.memoizedState;
      for(let n=0; hook && n<80; n++,hook=hook.next) {
        const data=hook.memoizedState;
        if(!Array.isArray(data)||!data.length||data.length>5000||!data.every(m=>m&&typeof m.id==='string'&&m.matchId===id&&typeof m.createdAt==='string'&&typeof m.senderId==='string'))continue;
        if(typeof hook.queue?.dispatch!=='function')continue;
        if(data.some((m,j)=>j>0&&compare(data[j-1],m)>0))hook.queue.dispatch(current=>{
          if(!Array.isArray(current)||!current.every(m=>m?.matchId===id))return current;
          return current.some((m,j)=>j>0&&compare(current[j-1],m)>0)?[...current].sort(compare):current;
        });
        return;
      }
    }
  }
  function update() {
    queued=false;
    const path=location.pathname, main=document.getElementById('main');
    if(path!==lastPath){seen=new WeakSet();initializedPane=null;if(roots.has(path))animate(main,[{opacity:.82},{opacity:1}]);lastPath=path;}
    const pane=document.querySelector('#main .card.relative.min-h-0.flex-1.overflow-y-auto')||document.querySelector('#main .messages');
    orderMessages(pane);
    if(pane){
      for(const bubble of pane.querySelectorAll('.bubble-me,.bubble-them'))if(!seen.has(bubble)){
        seen.add(bubble);if(initializedPane===pane)animate(bubble,[{opacity:.7,transform:'translateY(4px)'},{opacity:1,transform:'translateY(0)'}],170);
      }
      initializedPane=pane;
    }
    for(const dialog of document.querySelectorAll('[role="dialog"],dialog[open]'))if(!seen.has(dialog)){seen.add(dialog);animate(dialog,[{opacity:.85},{opacity:1}],140);}
  }
  function schedule(){if(!queued){queued=true;queueMicrotask(update);}}
  new MutationObserver(schedule).observe(document,{childList:true,subtree:true});
  window.addEventListener('popstate',schedule);
  document.addEventListener('pointerdown',event=>{
    const button=event.target.closest?.('#main button,#main [role="button"]');
    if(button&&!button.matches(':disabled,[aria-disabled="true"]')&&!button.closest('.stage'))animate(button,[{filter:'brightness(.92)'},{filter:'brightness(1)'}],160);
  },{passive:true});
  schedule();
})();
