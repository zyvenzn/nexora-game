// Pack opening: swipe to tear the pack, flip each card, then a summary.
// The result is decided by the server the moment you press Open; this file only plays the show.
import { rpc } from './api.js';
import { state, setMe } from './state.js';
import { el, emblem, packArt, cardEl, chip, rarityColor, rarityName, coin, fmt, toast, friendly, reducedMotion } from './ui.js';

const CUT = 15;     // where the tear line sits, percent from the top of the pack
const TEETH = 12;

function tearPolygons() {
  const zig = [];
  for (let i = 0; i <= TEETH; i++) zig.push([(i * 100 / TEETH), CUT + (i % 2 ? 1.5 : -1.5)]);
  const fmtPt = p => `${p[0].toFixed(2)}% ${p[1].toFixed(2)}%`;
  const top = ['0% 0%', '100% 0%', ...zig.slice().reverse().map(fmtPt)];
  const bottom = ['0% 100%', '100% 100%', ...zig.slice().reverse().map(fmtPt)];
  // top = everything above the jagged line, bottom = everything below it (same line, so the halves fit)
  return {
    top: 'polygon(' + top.join(',') + ')',
    bottom: 'polygon(' + ['0% 100%', ...zig.map(fmtPt), '100% 100%'].join(',') + ')'
  };
}

export async function openPack(packId) {
  const pt = state.packTypes[packId];
  if (!pt) { toast('That pack does not exist.', 'error'); return 'error'; }
  let res;
  try { res = await rpc('open_pack', { p_pack: packId }); }
  catch (e) { toast(friendly(e), 'error'); return 'error'; }
  setMe(res.me);
  return play(pt, res.cards);
}

/* ---------------------------------------------------------------- particles */
function makeFx(root) {
  const cv = el('canvas', { class: 'op__fx', 'aria-hidden': 'true' });
  root.append(cv);
  const ctx = cv.getContext('2d');
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  let parts = [], raf = 0, alive = true;
  const fit = () => { cv.width = innerWidth * dpr; cv.height = innerHeight * dpr; };
  fit(); window.addEventListener('resize', fit);
  function loop() {
    ctx.clearRect(0, 0, cv.width, cv.height);
    parts = parts.filter(p => p.life > 0);
    for (const p of parts) {
      p.x += p.vx; p.y += p.vy; p.vy += p.g; p.vx *= 0.99; p.life -= 1;
      ctx.globalAlpha = Math.max(0, Math.min(1, p.life / 30));
      ctx.fillStyle = p.c;
      const s = p.s * dpr;
      ctx.fillRect(Math.round(p.x * dpr / s) * s, Math.round(p.y * dpr / s) * s, s, s); // square, pixel-ish
    }
    raf = parts.length && alive ? requestAnimationFrame(loop) : 0;
    if (!raf) ctx.clearRect(0, 0, cv.width, cv.height);
  }
  return {
    burst(x, y, color, n, power = 1) {
      if (reducedMotion()) return;
      for (let i = 0; i < n; i++) {
        const a = Math.random() * Math.PI * 2, v = (2 + Math.random() * 6) * power;
        parts.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 2, g: 0.16, life: 40 + Math.random() * 40, s: 3 + Math.floor(Math.random() * 3),
                     c: Math.random() < 0.3 ? '#ffffff' : color });
      }
      if (!raf) raf = requestAnimationFrame(loop);
    },
    destroy() { alive = false; cancelAnimationFrame(raf); window.removeEventListener('resize', fit); cv.remove(); }
  };
}

/* ---------------------------------------------------------------- the show */
function play(pt, cards) {
  return new Promise(resolve => {
    const root = document.getElementById('overlay');
    const prevFocus = document.activeElement;
    const fx = makeFx(root);
    const flash = el('div', { class: 'op__flash', 'aria-hidden': 'true' });
    const closeBtn = el('button', { class: 'op__close', type: 'button' }, 'Skip');
    const stage = el('div', { class: 'op__stage' });
    const wrap = el('div', { class: 'op', role: 'dialog', 'aria-modal': 'true', 'aria-label': `Opening a ${pt.name}` }, flash, closeBtn, stage);
    root.append(wrap);
    document.body.classList.add('is-locked');
    let phase = 'tear', done = false;

    function finish(result) {
      if (done) return; done = true;
      document.removeEventListener('keydown', onKey);
      fx.destroy(); wrap.remove();
      document.body.classList.remove('is-locked');
      if (prevFocus && document.body.contains(prevFocus)) prevFocus.focus({ preventScroll: true });
      resolve(result);
    }
    function onKey(e) {
      if (e.key === 'Escape') { phase === 'summary' ? finish('done') : showSummary(); }
      if (e.key === 'Tab') { // keep focus inside the overlay
        const f = Array.from(wrap.querySelectorAll('button, a[href]')).filter(b => !b.disabled && b.offsetParent !== null);
        if (!f.length) return;
        const first = f[0], last = f[f.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    }
    document.addEventListener('keydown', onKey);
    closeBtn.addEventListener('click', () => phase === 'summary' ? finish('done') : showSummary());

    /* ---------- stage 1: tear ---------- */
    function showTear() {
      phase = 'tear';
      closeBtn.textContent = 'Skip';
      const poly = tearPolygons();
      const body = el('div', { class: 'tear__half tear__body' }, packArt(pt));
      const top = el('div', { class: 'tear__half tear__top' }, packArt(pt));
      body.style.clipPath = body.style.webkitClipPath = poly.bottom;
      top.style.clipPath = top.style.webkitClipPath = poly.top;
      const light = el('div', { class: 'tear__light', 'aria-hidden': 'true' });
      const tear = el('div', { class: 'tear', style: `--cut:${CUT}%` }, light, body, top);
      const hint = el('p', { class: 'op__hint' }, 'Swipe across the pack to tear it open');
      const track = el('div', { class: 'tear__track', 'aria-hidden': 'true' }, el('i'));
      const tapBtn = el('button', { class: 'btn btn--ghost', type: 'button' }, 'Tear it open');
      stage.replaceChildren(tear, hint, track, tapBtn);
      tapBtn.focus({ preventScroll: true });

      let startX = null, p = 0, opened = false;
      const setP = v => { p = Math.max(0, Math.min(1, v)); tear.style.setProperty('--p', p.toFixed(3)); track.firstChild.style.width = (p * 100) + '%'; };
      setP(0);
      tear.addEventListener('pointerdown', e => { if (opened) return; startX = e.clientX; tear.classList.add('is-dragging'); tear.setPointerCapture(e.pointerId); });
      tear.addEventListener('pointermove', e => {
        if (startX == null || opened) return;
        const w = tear.getBoundingClientRect().width;
        setP(Math.abs(e.clientX - startX) / (w * 0.75));
        if (navigator.vibrate && Math.random() < 0.15) navigator.vibrate(8);
      });
      const release = () => {
        if (startX == null || opened) return;
        startX = null; tear.classList.remove('is-dragging');
        if (p >= 0.55) rip(); else setP(0);
      };
      tear.addEventListener('pointerup', release);
      tear.addEventListener('pointercancel', release);
      tapBtn.addEventListener('click', rip);

      function rip() {
        if (opened) return; opened = true;
        tapBtn.disabled = true; hint.textContent = '';
        tear.classList.remove('is-dragging'); tear.classList.add('is-ripped');
        setP(1);
        if (navigator.vibrate) navigator.vibrate([20, 30, 40]);
        const r = tear.getBoundingClientRect();
        fx.burst(r.left + r.width / 2, r.top + r.height * (CUT / 100), '#ffe9a8', 40, 1.1);
        flash.classList.remove('is-on'); void flash.offsetWidth; flash.classList.add('is-on');
        setTimeout(() => showCards(0), reducedMotion() ? 0 : 750);
      }
    }

    /* ---------- stage 2: reveal cards one by one ---------- */
    function showCards(i) {
      if (done) return;
      phase = 'cards';
      closeBtn.textContent = 'Skip';
      const c = cards[i];
      const rar = state.rar[c.rarity];
      const glow = rarityColor(c.rarity);
      const back = el('span', { class: 'cardback' }, emblem('moon', '#d8cbff', '#fff'));
      const front = cardEl(c);
      const card = el('button', { class: 'rv__card', type: 'button', 'aria-label': 'Tap to reveal the card' },
        el('span', { class: 'rv__inner' },
          el('span', { class: 'rv__face rv__back' }, back),
          el('span', { class: 'rv__face rv__front' }, front)));
      card.style.setProperty('--glow', glow);
      const info = el('div', { class: 'rv__info', 'aria-live': 'polite' }, el('p', { class: 'rv__prompt' }, 'Tap the card'));
      const next = el('button', { class: 'btn', type: 'button', hidden: true }, i < cards.length - 1 ? 'Next card' : 'See all cards');
      const count = el('p', { class: 'rv__count' }, `Card ${i + 1} of ${cards.length}`);
      stage.replaceChildren(count, card, info, next);
      card.focus({ preventScroll: true });
      card.classList.add('is-entering');

      let flipped = false;
      card.addEventListener('click', () => {
        if (flipped) return; flipped = true;
        card.classList.add('is-flipped');
        card.setAttribute('aria-label', `${c.name}, ${rar.name}`);
        const r = card.getBoundingClientRect();
        const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
        setTimeout(() => {
          if (c.rank >= 1) fx.burst(cx, cy, glow, [0, 28, 60, 100, 170][c.rank] || 28, 0.8 + c.rank * 0.25);
          if (c.rank >= 2) { flash.style.setProperty('--flash', glow); flash.classList.remove('is-on'); void flash.offsetWidth; flash.classList.add('is-on'); }
          if (navigator.vibrate) navigator.vibrate(c.rank >= 2 ? [30, 40, 60] : 15);
        }, reducedMotion() ? 0 : 380);
        const lines = [
          chip(c.rarity),
          el('h3', { class: 'rv__name' }, c.name),
          el('p', { class: 'rv__blurb' }, c.blurb),
          el('p', { class: 'rv__meta' }, `#${c.serial} of this card`, ' · ', `worth ${coin(c.value)}`)
        ];
        if (c.is_new) lines.push(el('p', { class: 'rv__new' }, 'New to your collection'));
        info.replaceChildren(...lines);
        next.hidden = false; next.focus({ preventScroll: true });
      });
      next.addEventListener('click', () => (i < cards.length - 1 ? showCards(i + 1) : showSummary()));
    }

    /* ---------- stage 3: summary ---------- */
    function showSummary() {
      if (done) return;
      phase = 'summary';
      closeBtn.textContent = 'Close';
      const total = cards.reduce((s, c) => s + (c.value || 0), 0);
      const grid = el('div', { class: 'sm__grid' }, cards.map(c => {
        const cell = el('div', { class: 'sm__cell' }, cardEl(c, { mini: true, badge: c.is_new ? 'NEW' : null }),
          el('span', { class: 'sm__name' }, c.name));
        cell.style.setProperty('--glow', rarityColor(c.rarity));
        return cell;
      }));
      const left = state.packs[pt.id] || 0;
      const again = el('button', { class: 'btn', type: 'button' }, left > 0 ? `Open another (${left} left)` : 'Done');
      const coll = el('a', { class: 'btn btn--ghost', href: '#/collection' }, 'View collection');
      coll.addEventListener('click', () => finish('done'));
      again.addEventListener('click', () => finish(left > 0 ? 'again' : 'done'));
      const newCount = cards.filter(c => c.is_new).length;
      stage.replaceChildren(
        el('h2', { class: 'sm__title' }, pt.name.replace(/ Pack$/, '') + ' pack'),
        el('p', { class: 'sm__sub' }, `${newCount} new, worth ${coin(total)} in total`),
        grid, el('div', { class: 'op__actions' }, again, coll));
      again.focus({ preventScroll: true });
    }

    if (reducedMotion()) showCards(0); else showTear();
  });
}
