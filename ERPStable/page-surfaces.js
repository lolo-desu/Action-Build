(() => {
  'use strict';
  if (window!==window.top || location.origin!=='https://erp.sex') return;
  // The site already has an installed-app branch. Use that branch rather than
  // removing arbitrary translated text or intercepting its installation flow.
  try { Object.defineProperty(navigator,'standalone',{get:()=>true,configurable:true}); } catch {}
  const post=value=>{try{window.webkit?.messageHandlers?.erpNativeApp?.postMessage({...value,entryKey:window.__vrcrpEntryKey?.()||history.state?.key});}catch{}};
  const editing=()=>/^\/profile\/edit(?:\/|$)/.test(location.pathname);
  const chat=()=>/^\/matches\/[^/]+\/?$/.test(location.pathname);
  let unread=0,queued=false,overlay=null,lastOverlay=false,lastHeader='';
  const backIcon='<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true"><path d="m15 5-7 7 7 7"/></svg>';
  const css=`
    html[data-vrcrp-chat="true"] .app-top{display:none!important}
    html[data-vrcrp-chat="true"] #main{padding-top:0!important}
    [data-vrcrp-chat-bar]{position:sticky!important;top:0;z-index:45;flex-shrink:0;background:rgb(var(--surface))!important;border-radius:0!important;border-top:0!important;border-left:0!important;border-right:0!important;min-height:56px}
    [data-vrcrp-chat-back]{display:flex!important;align-items:center;gap:3px;min-width:40px;min-height:44px;flex-shrink:0}
    [data-vrcrp-unread]{display:inline-flex;justify-content:center;align-items:center;min-width:20px;height:20px;padding:0 4px;border-radius:10px;background:rgb(var(--primary));color:rgb(var(--fg));font:700 11px system-ui;border:1px solid currentColor}
    [data-vrcrp-unread][hidden]{display:none!important}
    [data-vrcrp-back-strip]{display:flex;align-items:center;gap:8px;min-height:44px;margin-bottom:8px;color:rgb(var(--fg));background:rgb(var(--surface));border-radius:12px;padding:0 8px}
    button[data-vrcrp-page-back]{display:inline-flex;align-items:center;justify-content:center;min-width:44px;min-height:44px;background:transparent;color:inherit;border:0;border-radius:10px;touch-action:manipulation}
    #main[data-vrcrp-pulling]{transform:translateY(var(--vrcrp-pull-space,0px))}
    [data-vrcrp-install]{display:none!important}
  `;
  function chatHeader(main){
    const link=main?.querySelector('a[href^="/u/"]');
    const card=link?.closest('.card');
    return card?.querySelector('button')&&card.contains(link)?card:main?.querySelector('.chat-header');
  }
  function updateUnread(){
    const button=document.querySelector('[data-vrcrp-chat-back]');if(!button)return;
    let badge=button.querySelector('[data-vrcrp-unread]');
    if(!badge){badge=document.createElement('span');badge.dataset.vrcrpUnread='true';button.appendChild(badge);}
    const text=unread>99?'99+':String(unread);if(badge.textContent!==text)badge.textContent=text;badge.hidden=unread===0;
    const title=button.dataset.vrcrpBackLabel||button.getAttribute('aria-label')||'返回';
    button.dataset.vrcrpBackLabel=title;const label=unread?`${title}，${unread} 条未读消息`:title;if(button.getAttribute('aria-label')!==label)button.setAttribute('aria-label',label);
  }
  window.__vrcrpChatUnread=count=>{if(Number.isSafeInteger(count)&&count>=0&&count<=100000){unread=count;updateUnread();}};
  function pageBack(main){
    if(!editing()&&!/^\/u\/[^/]+/.test(location.pathname))return;
    const heading=main?.querySelector('h1');if(!heading)return;
    const group=heading.closest('.flex.items-center')||heading.parentElement.parentElement;
    const original=[...group.querySelectorAll('button')].find(b=>/^(返回|返回上一页|上一頁|返回上頁|back|go back)$/i.test((b.getAttribute('aria-label')||b.title||'').trim()));
    if(original){original.dataset.vrcrpPageBack='true';return;}
    if(main.querySelector('[data-vrcrp-page-back]'))return;
    const button=document.createElement('button');button.type='button';button.dataset.vrcrpPageBack='true';button.setAttribute('aria-label','返回');button.innerHTML=backIcon;
    button.addEventListener('click',()=>{if(!window.__vrcrpBack?.())window.__vrcrpOpenRoot?.('/me');});
    if(group.classList.contains('flex')&&group.classList.contains('items-center'))group.prepend(button);
    else{const strip=document.createElement('div');strip.dataset.vrcrpBackStrip='true';const label=document.createElement('span');label.textContent=editing()?'编辑名片':'名片详情';strip.append(button,label);main.prepend(strip);}
  }
  function update(){
    queued=false;const root=document.documentElement;if(!root||!document.head)return;
    if(!document.getElementById('vrcrp-page-surfaces')){const style=document.createElement('style');style.id='vrcrp-page-surfaces';style.textContent=css;document.head.appendChild(style);}
    root.dataset.vrcrpChat=String(chat());const main=document.getElementById('main');
    const header=chat()?chatHeader(main):document.querySelector('.app-top');
    if(chat()&&header){header.dataset.vrcrpChatBar='true';const back=header.querySelector('button');if(back){back.dataset.vrcrpChatBack='true';updateUnread();}}
    pageBack(main);
    overlay=['/discover','/browse','/visitors'].includes(location.pathname)?main?.querySelector('.fixed.inset-0.overflow-y-auto.overscroll-contain'):null;
    if(overlay&&!overlay.querySelector('.sticky button'))overlay=null;
    if(overlay)overlay.dataset.vrcrpProfileOverlay='true';
    const visible=!!overlay;if(visible!==lastOverlay){lastOverlay=visible;post({kind:'profileOverlay',visible});}
    if(header){const r=header.getBoundingClientRect(),style=getComputedStyle(header);const values=style.backgroundColor.match(/[\d.]+/g)?.map(Number)||[255,255,255,1];const geometry={kind:'pageHeader',height:Math.max(0,r.height),color:[values[0]/255,values[1]/255,values[2]/255,values[3]??1]};const fp=JSON.stringify(geometry);if(fp!==lastHeader){lastHeader=fp;post(geometry);}}
    for(const button of document.querySelectorAll('button,[role="button"],a')){
      if(button.closest('[data-vrcrp-install]'))continue;
      const title=(button.getAttribute('aria-label')||button.textContent||'').trim();
      if(title.length<80&&/^(?:添加|加入|新增|加到).*(?:主屏幕|主螢幕|主界面|主屏幕画面|主画面|主畫面|桌面)|^(?:add to home screen|install app|安装应用|安裝應用)$/i.test(title))button.dataset.vrcrpInstall='true';
    }
  }
  function schedule(){if(!queued){queued=true;requestAnimationFrame(update);}}
  window.__vrcrpRefreshSurface=update;
  window.__vrcrpCloseProfileOverlay=()=>{update();const close=overlay?.querySelector('.sticky button');if(!close)return false;document.activeElement?.blur?.();close.click();queueMicrotask(update);return true;};
  window.__vrcrpPageBack=()=>{
    update();
    if(overlay)return window.__vrcrpCloseProfileOverlay();
    if(window.__vrcrpBack?.())return true;
    const button=document.querySelector('#main [data-vrcrp-page-back]');
    if(button){document.activeElement?.blur?.();button.click();return true;}return false;
  };
  window.__vrcrpPullSurface=space=>{const main=document.getElementById('main');if(!main)return;const amount=Math.max(0,Math.min(72,Number(space)||0));main.style.transition=amount||matchMedia('(prefers-reduced-motion: reduce)').matches?'none':'transform 160ms ease-out';main.style.setProperty('--vrcrp-pull-space',`${amount}px`);if(amount)main.dataset.vrcrpPulling='true';else main.removeAttribute('data-vrcrp-pulling');};
  document.addEventListener('click',event=>{if(event.target.closest?.('[data-vrcrp-chat-back],[data-vrcrp-page-back]')&&window.__vrcrpBack?.()){event.preventDefault();event.stopImmediatePropagation();}},true);
  new MutationObserver(records=>{if(records.some(r=>r.type!=='attributes'||!r.attributeName.startsWith('data-vrcrp')))schedule();}).observe(document,{subtree:true,childList:true,attributes:true,attributeFilter:['class','aria-label','data-vrcrp-chat'],characterData:true});
  window.addEventListener('popstate',schedule);window.addEventListener('resize',schedule);schedule();
})();
