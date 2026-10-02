(() => {
  'use strict';
  if(window!==window.top || location.origin!=='https://erp.sex')return;
  const css=`html[data-vrcrp-app="true"] .stage [data-vrcrp-stamp]{background:#fff !important;box-shadow:0 4px 18px #0005,0 0 0 2px #fff8;font-weight:900 !important;font-size:clamp(28px,8vw,34px) !important;line-height:1.12;padding:7px 12px !important;z-index:30 !important;pointer-events:none !important;opacity:var(--vrcrp-stamp-opacity);}
  html[data-vrcrp-app="true"] .stage [data-vrcrp-stamp="super"]{bottom:28% !important;color:#141414 !important;}
  html[data-vrcrp-app="true"] .stage [data-vrcrp-stamp].vrcrp-drag-stamp{opacity:var(--vrcrp-stamp-opacity) !important;}`;
  let drag=null,frame=0;
  function label(card){
    const labels=[...card.querySelectorAll('span.pointer-events-none.absolute.border-4')];
    for(const el of labels){
      const kind=el.classList.contains('border-success')?'like':el.classList.contains('border-danger')?'pass':el.classList.contains('border-accent')?'super':null;
      if(kind)el.dataset.vrcrpStamp=kind;
    }
    return labels.filter(el=>el.dataset.vrcrpStamp);
  }
  function install(){if(!document.head || document.getElementById('vrcrp-swipe-feedback'))return;const style=document.createElement('style');style.id='vrcrp-swipe-feedback';style.textContent=css;document.head.appendChild(style);}
  function reset(){if(!drag)return;for(const el of drag.labels){el.classList.remove('vrcrp-drag-stamp');el.style.removeProperty('--vrcrp-stamp-opacity');}drag=null;cancelAnimationFrame(frame);}
  function update(){
    if(!drag || !drag.card.isConnected){reset();return;}
    let x=0,y=0;try{const matrix=new DOMMatrixReadOnly(getComputedStyle(drag.card).transform);x=matrix.m41;y=matrix.m42;}catch{}
    const up=-y>Math.abs(x);
    for(const el of drag.labels){const kind=el.dataset.vrcrpStamp;let amount=kind==='super'?(up?-y:0):up?0:kind==='like'?x:-x;const opacity=Math.min(1,Math.max(0,(amount-8)/48));el.style.setProperty('--vrcrp-stamp-opacity',String(opacity));el.classList.add('vrcrp-drag-stamp');}
    frame=requestAnimationFrame(update);
  }
  document.addEventListener('pointerdown',event=>{
    if(location.pathname!=='/discover' || event.isPrimary===false || event.button!==0)return;
    const card=event.target.closest?.('.stage .cursor-grab');if(!card || event.target.closest('button,input,textarea,a'))return;
    reset();install();const labels=label(card);if(!labels.length)return;drag={id:event.pointerId,card,labels};frame=requestAnimationFrame(update);
  },{passive:true,capture:true});
  for(const event of ['pointerup','pointercancel'])document.addEventListener(event,e=>{if(drag?.id===e.pointerId)reset();},{passive:true,capture:true});
  document.addEventListener('DOMContentLoaded',install);install();
})();
