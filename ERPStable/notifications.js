(() => {
  'use strict';
  const bridge = window.webkit?.messageHandlers?.erpNativeNotifications;
  if (window !== window.top || location.origin !== 'https://erp.sex' || !bridge) return;
  const originalFetch = window.fetch, OriginalWebSocket = window.WebSocket;
  const seen = new Set(), matches = new Map();
  let userId = '', unread = null, socket = null, active = true, busy = false;
  let pollTimer = null, fallbackTimer = null, lastDetailed = 0, sessionStarted = Date.now();
  let epoch = 0, controller = null, retryDelay = 0;
  let requestHeaders = { Accept: 'application/json', 'X-Content-Mode': 'sfw' };
  function post(value) { try { bridge.postMessage(value); } catch {} }
  function validId(value) { return typeof value === 'string' && /^[\w-]{1,120}$/.test(value); }
  function unwrap(value) { return value?.data ?? value; }
  function remember(id) { seen.add(id); if (seen.size > 512) seen.delete(seen.values().next().value); }
  function body(message) {
    if (message.type === 'image') return '[图片]';
    if (message.type === 'voice') return '[语音]';
    if (message.type === 'vrc_link') return '[VRChat 链接]';
    if (message.type === 'system') return '有新的聊天动态';
    return Array.from(typeof message.text === 'string' ? message.text : '你有新的聊天消息').slice(0,140).join('');
  }
  function message(value, title) {
    if (!userId || !validId(value?.id) || !validId(value?.matchId) || seen.has(value.id)) return;
    remember(value.id);
    if (value.recalled || String(value.senderId) === userId) return;
    lastDetailed = Date.now(); clearTimeout(fallbackTimer);
    if (active && !document.hidden && location.pathname === '/matches/' + value.matchId) return;
    post({ kind: 'chatMessage', messageId: value.id, matchId: value.matchId, senderId: String(value.senderId ?? ''), title: String(title || matches.get(value.matchId)?.title || '新聊天消息').slice(0,80), body: body(value) });
  }
  function counters(value) {
    const count = value?.unreadMessages;
    if (!Number.isSafeInteger(count) || count < 0 || count > 100000) return;
    const increased = unread !== null && count > unread;
    unread = count; post({ kind: 'counters', unread: count });
    if (increased && Date.now() - lastDetailed > 3000) {
      clearTimeout(fallbackTimer);
      fallbackTimer = setTimeout(() => { if (Date.now() - lastDetailed > 3000) post({ kind: 'genericMessage', unread }); }, 2200);
    }
  }
  function session(value) {
    const id = value?.id == null ? '' : String(value.id);
    if (id === userId) { if (id) postSession(); return; }
    if (userId) socket = null;
    epoch++; controller?.abort();
    userId = validId(id) ? id : ''; unread = null; seen.clear(); matches.clear(); sessionStarted = Date.now();
    clearTimeout(fallbackTimer); clearTimeout(pollTimer);
    postSession(); if (userId) schedule(0);
  }
  function postSession() { post({ kind: 'session', userId, mode: requestHeaders['X-Content-Mode'], language: requestHeaders['Accept-Language'] || navigator.language || 'en', userAgent: navigator.userAgent }); }
  function snapshot(value) {
    if (!userId || !Array.isArray(value?.items)) return;
    const summaries = [];
    for (const item of value.items.slice(0,200)) {
      const id = String(item.id ?? ''), latest = item.lastMessage;
      if (!validId(id)) continue;
      const title = String(item.user?.displayName || '新聊天消息').slice(0,80), prior = matches.get(id);
      const created = Date.parse(latest?.createdAt);
      if (latest?.id && prior && prior.messageId !== latest.id && item.unreadCount > 0) message({ ...latest, matchId: id }, title);
      else if (latest?.id && !prior && Number.isFinite(created) && created >= sessionStarted && item.unreadCount > 0) message({ ...latest, matchId: id }, title);
      if (latest?.id) remember(latest.id);
      matches.set(id,{ title, messageId: latest?.id });
      summaries.push({ matchId: id, title, messageId: latest?.id || '', unread: item.unreadCount || 0 });
    }
    post({ kind: 'snapshot', items: summaries });
  }
  function refreshList() {
    // Use the site's existing subscription to invalidate its React Query list.
    // This is local only: no fake messages or read acknowledgements are sent.
    if (active && !document.hidden && socket) socket.dispatchEvent(new MessageEvent('message',{data:JSON.stringify({type:'match.updated',data:{}})}));
  }
  async function sync() {
    if (!userId || !active || document.hidden || busy || !navigator.onLine) return;
    busy = true;
    const owner = epoch;
    controller = new AbortController();
    const timeout = setTimeout(() => controller?.abort(), 12000);
    try {
      const options = { credentials: 'include', cache: 'no-store', headers: requestHeaders, signal: controller.signal };
      const responses = await Promise.all([originalFetch.call(window,'/api/v1/me/counters',options),originalFetch.call(window,'/api/v1/matches?state=active',options)]);
      if (owner !== epoch) return;
      if (responses.some(r => r.status === 401)) { session(null); return; }
      retryDelay = responses.some(r => r.status === 429 || r.status >= 500) ? 30000 : 0;
      for (const r of responses) if (r.status === 429) retryDelay = Math.max(retryDelay, Math.min(120000, (Number(r.headers.get('Retry-After')) || 30) * 1000));
      for (let i=0;i<responses.length;i++) if (responses[i].ok) {
        const value = unwrap(await responses[i].json()); if (owner !== epoch) return;
        i === 0 ? counters(value) : snapshot(value);
        if (i === 0 && socket) socket.dispatchEvent(new MessageEvent('message',{data:JSON.stringify({type:'counters',data:value})}));
      }
      if (location.pathname === '/matches' && responses[1].ok) refreshList();
    } catch { retryDelay = 30000; } finally { busy = false; controller = null; clearTimeout(timeout); }
  }
  function schedule(delay) {
    clearTimeout(pollTimer);
    if (!userId || !active || document.hidden) return;
    pollTimer = setTimeout(async () => { await sync(); schedule(Math.max(retryDelay, location.pathname === '/matches' ? 5000 : 15000)); }, delay);
  }
  window.__vrcrpSyncChats = () => { if (!busy) schedule(0); };
  window.__vrcrpAppActive = value => { active = value === true; if (active) schedule(0); else clearTimeout(pollTimer); };
  window.fetch = function (...args) {
    const owner = epoch;
    const result = Reflect.apply(originalFetch,this,args);
    let url, method;
    try {
      url = new URL(args[0] instanceof Request ? args[0].url : String(args[0]),location.href);
      method = String(args[1]?.method || (args[0] instanceof Request ? args[0].method : 'GET')).toUpperCase();
      if (url.origin === location.origin && url.pathname.startsWith('/api/v1/')) {
        const h = new Headers(args[1]?.headers || (args[0] instanceof Request ? args[0].headers : {}));
        const mode = h.get('X-Content-Mode'), language = h.get('Accept-Language');
        const changed = mode && mode !== requestHeaders['X-Content-Mode'] || language && language !== requestHeaders['Accept-Language'];
        if (['sfw','mixed','r18'].includes(mode)) requestHeaders['X-Content-Mode'] = mode;
        if (language && language.length < 80) requestHeaders['Accept-Language'] = language;
        if (changed && userId) postSession();
      }
    } catch {}
    if (url?.origin === location.origin) result.then(response => {
      if (owner !== epoch) return;
      if (url.pathname === '/api/v1/me' && response.status === 401 || url.pathname === '/api/v1/auth/logout' && response.ok) { session(null); return; }
      if (!response.ok || method !== 'GET') return;
      if (['/api/v1/me','/api/v1/me/counters','/api/v1/matches'].includes(url.pathname)) response.clone().json().then(data => {
        if (owner !== epoch) return;
        const value = unwrap(data);
        if (url.pathname === '/api/v1/me') session(value);
        else if (url.pathname.endsWith('/counters')) counters(value);
        else snapshot(value);
      }).catch(()=>{});
    }).catch(()=>{});
    return result;
  };
  window.WebSocket = new Proxy(OriginalWebSocket,{
    construct(target,args,newTarget) {
      const connection = Reflect.construct(target,args,newTarget);
      let url; try { url = new URL(String(args[0]),location.href); } catch {}
      if (url?.protocol === 'wss:' && url.host === location.host && url.pathname === '/api/v1/ws') {
        socket = connection;
        connection.addEventListener('message',event => { try {
          if (connection !== socket) return;
          const value = JSON.parse(event.data);
          if (value.type === 'counters') counters(value.data);
          else if (value.type === 'message.new') { message(value.data); if (location.pathname === '/matches') setTimeout(refreshList,0); schedule(1000); }
          else if (['match.new','match.updated','match.closed'].includes(value.type)) schedule(1000);
        } catch {} });
        connection.addEventListener('open',()=>schedule(0));
        connection.addEventListener('close',()=>schedule(1000));
      }
      return connection;
    }
  });
  document.addEventListener('visibilitychange',()=>{ if (!document.hidden) schedule(0); else clearTimeout(pollTimer); });
  window.addEventListener('online',()=>schedule(0));
  window.addEventListener('popstate',()=>schedule(0));
})();
