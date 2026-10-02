(() => {
  'use strict';
  if (window !== window.top || location.origin !== 'https://erp.sex' || !window.webkit?.messageHandlers?.erpNativeApp) return;
  const network = window.fetch, bodies = new Map(), flights = new Map(), ownedControllers = new Set();
  let user = '', epoch = 0, queryClient = null, bus = null, importing = false, active = true;
  let headers = { Accept: 'application/json', 'X-Content-Mode': 'sfw' };
  let warmVisit = '', warmCount = 0;
  const pendingEvents=[];
  const idOK = value => typeof value === 'string' && /^[\w-]{1,120}$/.test(value);
  const unwrap = value => value?.data ?? value;
  function configure(next) {
    const mode = next['X-Content-Mode'] || headers['X-Content-Mode'];
    const language = next['Accept-Language'] || headers['Accept-Language'] || '';
    if (mode !== headers['X-Content-Mode'] || language !== (headers['Accept-Language'] || '')) { epoch++;for(const c of ownedControllers)c.abort(); bodies.clear(); flights.clear(); warmVisit = ''; warmCount = 0; }
    headers = { ...headers, ...next };
  }
  const isClient = value => value && typeof value.getQueryCache === 'function' && typeof value.setQueryData === 'function' && typeof value.invalidateQueries === 'function';
  function client() {
    if (!queryClient) {
      // Read the existing provider; all changes use TanStack's public methods.
      // If React changes this attachment, the WS/refetch fallback remains usable.
      const root = document.getElementById('root');
      const key = root && Object.keys(root).find(k => k.startsWith('__reactContainer$'));
      const fiber = key && root[key];
      const queue = fiber ? [fiber.stateNode?.current || fiber] : [];
      const visited = new Set();
      for (let n = 0; queue.length && n < 500; n++) {
        const node = queue.shift(); if (!node || visited.has(node)) continue; visited.add(node);
        const value = node.memoizedProps?.value;
        if (isClient(value)) { queryClient = value; break; }
        if (node.child) queue.push(node.child); if (node.sibling) queue.push(node.sibling);
      }
    }
    if (!queryClient || !user || String(queryClient.getQueryData(['me'])?.id || '') !== user) return null;
    return queryClient;
  }
  function scopes(c) {
    const queries = c.getQueryCache().getAll().filter(q => Array.isArray(q.queryKey) && q.queryKey[0] === 'm' && q.queryKey[1] === headers['X-Content-Mode']);
    if(headers['Accept-Language'])return queries.filter(q=>q.queryKey[2]===headers['Accept-Language']);
    const observed=queries.filter(q=>q.getObserversCount()>0);return observed.length?observed:queries;
  }
  function commitCounters(value) {
    const c = client(); if (!c || !value || !Number.isSafeInteger(value.unreadMessages)) return false;
    c.setQueryData(['counters'], value); return true;
  }
  function commitMatches(value, state = 'active') {
    const c = client(); if (!c || !Array.isArray(value?.items)) return false;
    let applied = false;
    for (const q of scopes(c)) {
      const k = q.queryKey;
      if (k[3] !== 'matches' || k[4] !== state || k.length !== 5) continue;
      c.setQueryData(k, old => {
        if (!old?.pages?.length || !Array.isArray(old.pages[0]?.items)) return old;
        applied = true;
        const firstIDs = new Set(value.items.map(i => i.id));
        const displaced = old.pages[0].items.filter(i => !firstIDs.has(i.id));
        const seen = new Set(firstIDs);
        const rest = old.pages.slice(1).map((page, index) => ({ ...page, items: [...(index === 0 ? displaced : []), ...page.items].filter(i => { if (seen.has(i.id)) return false; seen.add(i.id); return true; }) }));
        return { ...old, pages: [value, ...rest] };
      });
      // Keep cursor boundaries correct when the user has loaded later pages.
      if (q.state.data?.pages?.length > 1) c.invalidateQueries({ queryKey: k, exact: true, refetchType: 'active' }).catch(() => {});
    }
    return applied;
  }
  function commitDetail(id, value) {
    const c = client(); if (!c || !value || value.id && value.id !== id) return;
    const list = scopes(c);
    const prefixes = new Map(list.map(q => [JSON.stringify(q.queryKey.slice(0,3)), q.queryKey.slice(0,3)]));
    for (const prefix of prefixes.values()) c.setQueryData([...prefix, 'matches', 'detail', id], value);
  }
  function refreshList() {
    const c = client(); if (!c) return emit('match.updated', {});
    c.invalidateQueries({ predicate: q => q.queryKey[0] === 'm' && q.queryKey[3] === 'matches' && q.queryKey.length === 5, refetchType: 'active' }).catch(() => {});
    return true;
  }
  function findBus() {
    if (bus || importing || !queryClient) return;
    const script = [...document.querySelectorAll('script[type="module"][src]')].find(s => new URL(s.src, location.href).origin === location.origin && /\/assets\/index-[^/]+\.js$/.test(new URL(s.src, location.href).pathname));
    if (!script) return;
    importing = true;
    // This is the already executed module URL, so import reuses its instance.
    import(script.src).then(module => {
      bus = Object.values(module).find(v => v && typeof v.on === 'function' && typeof v.emit === 'function' && typeof v.resume === 'function' && ['open','closed','connecting'].includes(v.status)) || null;
      if(bus){for(const event of pendingEvents.splice(0))if(event.owner===epoch)bus.emit(event.type,event.value);}
    }).catch(() => {}).finally(() => { importing = false; });
  }
  function emit(type, value) {
    client(); findBus();
    if (bus) { bus.emit(type, value); return true; }
    if(window.__vrcrpDispatchServerEvent?.(type, value)===true)return true;
    if(importing && JSON.stringify(value).length<32768){pendingEvents.push({owner:epoch,type,value});if(pendingEvents.length>60)pendingEvents.shift();return true;}
    return false;
  }
  function descriptor(url, method = 'GET') {
    if (method !== 'GET' || url.origin !== location.origin || !user) return null;
    const m = url.pathname.match(/^\/api\/v1\/matches\/([\w-]{1,120})(\/messages)?$/);
    if (!m) {
      if (!/^\/api\/v1\/(notifications|posts|worlds|users|profiles|likes|visitors)(?:\/|$)/.test(url.pathname)) return null;
      if (/\/(auth|token|export|download|check|verify)(?:\/|$)/.test(url.pathname)) return null;
      return { page:true, url, key:JSON.stringify([user,headers['X-Content-Mode'],headers['Accept-Language'] || '',url.pathname+url.search]) };
    }
    if (m[2] && (url.searchParams.has('before') || url.searchParams.has('after') || url.searchParams.get('limit') && url.searchParams.get('limit') !== '50')) return null;
    return { id: m[1], messages: !!m[2], url, key: JSON.stringify([user,headers['X-Content-Mode'],headers['Accept-Language'] || '',url.pathname + url.search]) };
  }
  function save(d, response, raw, prior) {
    if (!response.ok || response.status !== 200) return;
    const value = unwrap(raw);
    if (d.messages ? !Array.isArray(value?.items) : !value || typeof value !== 'object') return;
    const text = JSON.stringify(raw); if (text.length > 1024 * 1024) return;
    bodies.delete(d.key); bodies.set(d.key,{ d, raw, text, at: Date.now(), headers: [...response.headers] });
    while (bodies.size > 32 || [...bodies.values()].reduce((n,b) => n + b.text.length,0) > 6 * 1024 * 1024) bodies.delete(bodies.keys().next().value);
    if (d.page) {
      const c=client();
      // Update already-existing notification queries after validating warm data.
      // Do not guess keys for unrelated profile, post or world queries.
      if(c && d.url.pathname==='/api/v1/notifications' && !d.url.searchParams.has('cursor')) {
        for(const q of c.getQueryCache().getAll())if(q.queryKey.some(k=>k==='notifications') && (q.queryKey[0]!=='m'||q.queryKey[1]===headers['X-Content-Mode']&&(!headers['Accept-Language']||q.queryKey[2]===headers['Accept-Language']))) {
          c.setQueryData(q.queryKey,old=>{
            if(!old)return old;
            if(old.pages?.length&&Array.isArray(value.items))return {...old,pages:[value,...old.pages.slice(1)]};
            return Array.isArray(old.items)&&Array.isArray(value.items)?value:old;
          });
        }
      }
    } else if (!d.messages) commitDetail(d.id, value);
    else if (prior && location.pathname === '/matches/' + d.id) {
      const old = new Map((unwrap(prior.raw)?.items || []).map(m => [m.id,m]));
      for (const m of value.items) {
        if (!idOK(m.id)) continue;
        const before = old.get(m.id);
        if (!before || JSON.stringify(before) !== JSON.stringify(m)) emit('message.new', { ...m, matchId: d.id });
        if (m.recalled && !before?.recalled) emit('message.recalled',{matchId:d.id,messageId:m.id});
      }
    }
  }
  function request(d, args, receiver = window) {
    if (flights.has(d.key)) return flights.get(d.key).then(r => r.clone());
    const owner = epoch, prior = bodies.get(d.key);
    const result = Reflect.apply(network, receiver, args);
    const owned = result.then(r => r.clone()); flights.set(d.key, owned);
    owned.then(response => {
      if (response.status === 401 && owner === epoch) reset('');
      if (!response.ok) return;
      return response.clone().json().then(raw => { if (owner === epoch) save(d, response, raw, prior); });
    }).catch(() => {}).finally(() => { if (flights.get(d.key) === owned) flights.delete(d.key); });
    return result;
  }
  function get(url) {
    const resolved = new URL(url, location.href), d = descriptor(resolved);
    if (!d) return Promise.resolve(null);
    const control=new AbortController();ownedControllers.add(control);const timeout=setTimeout(()=>control.abort(),9000);
    return request(d,[resolved.href,{credentials:'include',headers,cache:'no-store',signal:control.signal}]).finally(()=>{clearTimeout(timeout);ownedControllers.delete(control);});
  }
  window.fetch = function (...args) {
    let d, mutation, signal, method = 'GET';
    try {
      const request = args[0] instanceof Request ? args[0] : null;
      signal=args[1]?.signal || request?.signal;
      const url = new URL(request?.url || String(args[0]),location.href);
      method = String(args[1]?.method || request?.method || 'GET').toUpperCase();
      if (url.origin === location.origin && url.pathname.startsWith('/api/v1/')) {
        const h = new Headers(args[1]?.headers || request?.headers || {});
        const next = {};
        if (['sfw','mixed','r18'].includes(h.get('X-Content-Mode'))) next['X-Content-Mode'] = h.get('X-Content-Mode');
        if (h.get('Accept-Language')) next['Accept-Language'] = h.get('Accept-Language');
        configure(next);
        if(method!=='GET'&&/^\/api\/v1\/(notifications|posts|worlds|users|profiles|likes|visitors)(?:\/|$)/.test(url.pathname)) {
          const category=url.pathname.split('/')[3];
          for(const [key,b] of bodies)if(b.d.page&&b.d.url.pathname.split('/')[3]===category)bodies.delete(key);
        }
        if (method !== 'GET' && /^\/api\/v1\/(matches|messages|auth)\//.test(url.pathname)) {
          const match = url.pathname.match(/^\/api\/v1\/matches\/([\w-]+)(?:\/|$)/);
          const recall = url.pathname.match(/^\/api\/v1\/messages\/([\w-]+)\/recall$/);
          if (recall) for (const [key,b] of bodies) if (b.d.messages && unwrap(b.raw)?.items?.some(m => m.id === recall[1])) bodies.delete(key);
          if (match && url.pathname.endsWith('/messages') && method === 'POST') mutation = match[1];
          else if (match && !url.pathname.endsWith('/read')) invalidate(match[1]);
        }
      }
      d = descriptor(url,method);
    } catch {}
    if (!d || args[1]?.cache === 'reload' || signal?.aborted) {
      const owner = epoch, result = Reflect.apply(network,this,args);
      if (mutation) result.then(response => { if (response.ok) response.clone().json().then(raw => { if (owner === epoch) serverEvent('message.new',{...unwrap(raw),matchId:mutation}); }).catch(() => {}); }).catch(() => {});
      return result;
    }
    const cached = bodies.get(d.key), maxAge = d.messages ? 90000 : d.page ? 300000 : 30000;
    if (cached && Date.now() - cached.at < maxAge) {
      const owner = epoch;
      // Serve the warm page immediately; validate in the background.
      if (active && !document.hidden && Date.now() - cached.at > 1200) request(d,args,this).catch(() => {});
      return Promise.resolve().then(() => {
        if (owner !== epoch) return Reflect.apply(network,this,args);
        if (signal?.aborted) throw new DOMException('Aborted','AbortError');
        return new Response(cached.text,{status:200,headers:cached.headers});
      });
    }
    return request(d,args,this);
  };
  function reset(id) {
    if (user !== id) { epoch++;for(const c of ownedControllers)c.abort(); bodies.clear(); flights.clear(); queryClient = null; bus = null; warmVisit = ''; warmCount = 0; }
    user = idOK(id) ? id : '';
  }
  function invalidate(id) { for (const [k,b] of bodies) if (b.d.id === id) bodies.delete(k); }
  function serverEvent(type, value) {
    if (!user) return;
    if (['match.closed','match.updated','message.recalled','account.updated'].includes(type)) {
      if (idOK(value?.matchId)) invalidate(value.matchId); else if (type === 'account.updated') bodies.clear();
    }
    if (type === 'message.new' && idOK(value?.id) && idOK(value?.matchId)) {
      for (const b of bodies.values()) if (b.d.messages && b.d.id === value.matchId) {
        const payload = unwrap(b.raw), map = new Map(payload.items.map(m => [m.id,m])); map.set(value.id,value);
        const all = [...map.values()].sort((a,b) => String(a.createdAt).localeCompare(String(b.createdAt)) || a.id.localeCompare(b.id));
        payload.items = all.slice(-50); payload.hasMore = payload.hasMore || all.length > 50;
        b.text = JSON.stringify(b.raw);
      }
    }
  }
  function prefetch(id) {
    if (!user || !idOK(id) || !active || document.hidden) return;
    for (const suffix of ['', '/messages?limit=50']) {
      const url = '/api/v1/matches/' + id + suffix, d = descriptor(new URL(url,location.href));
      if (!d) continue;
      const b = bodies.get(d.key);
      if (!b || Date.now() - b.at > (d.messages ? 60000 : 15000)) get(url).catch(() => {});
    }
  }
  function warmList(value) {
    if (location.pathname !== '/matches' || !Array.isArray(value?.items)) return;
    const visit = history.state?.key || 'initial';
    if (warmVisit !== visit) { warmVisit = visit; warmCount = 0; }
    if (warmCount) return;
    warmCount = 1; value.items.slice(0,3).forEach(item => prefetch(item.id));
  }
  window.__vrcrpSiteCache = {
    session(id, nextHeaders) { reset(id); if (nextHeaders) configure(nextHeaders); },
    active(value) { active = value === true; }, commitCounters, commitMatches, refreshList, warmList, prefetch, serverEvent,
    refreshPage() {
      const c=client();if(!c)return false;
      for(const [key,b] of bodies)if(b.d.page)bodies.delete(key);
      return c.invalidateQueries({refetchType:'active'}).then(()=>true,()=>true);
    },
    states() { const c = client(); return c ? [...new Set(scopes(c).filter(q => q.getObserversCount() > 0 && q.queryKey[3] === 'matches' && q.queryKey.length === 5).map(q => q.queryKey[4]))].filter(s => s === 'active' || s === 'unmatched') : ['active']; },
    async refreshChat() {
      const m = location.pathname.match(/^\/matches\/([\w-]{1,120})$/); if (!m || !active || document.hidden) return;
      await Promise.allSettled([get('/api/v1/matches/'+m[1]),get('/api/v1/matches/'+m[1]+'/messages?limit=50')]);
    },
    clear() { epoch++;for(const c of ownedControllers)c.abort(); bodies.clear(); flights.clear(); queryClient = null; bus = null; }
  };
  document.addEventListener('pointerdown',event => {
    const a = event.target?.closest?.('a[href]'); if (!a) return;
    try { const url = new URL(a.href,location.href), m = url.pathname.match(/^\/matches\/([\w-]{1,120})$/); if (url.origin === location.origin && m) prefetch(m[1]); } catch {}
  },{capture:true,passive:true});
})();
