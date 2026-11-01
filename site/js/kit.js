// Shared pieces for the market, auction, trade and craft pages.
import { el, cardEl, coin, rarityColor } from './ui.js';
import { state } from './state.js';

export const ELEMENTS = ['celestial', 'ember', 'tide', 'void'];
export const cap = s => (s ? s[0].toUpperCase() + s.slice(1) : '');
// Re-run the current page (the router listens for hashchange).
export const refreshRoute = () => window.dispatchEvent(new Event('hashchange'));

export function marketNav(active) {
  const items = [['market', 'Market'], ['auctions', 'Auctions'], ['trades', 'Trades'], ['craft', 'Craft']];
  const inc = (state.me && state.me.incoming_trades) || 0;
  return el('div', { class: 'seg' }, items.map(([k, t]) =>
    el('a', { class: 'seg__item' + (k === active ? ' is-on' : ''), href: '#/' + k }, t,
      k === 'trades' && inc > 0 ? el('span', { class: 'dot', 'aria-label': inc + ' waiting' }, String(inc)) : null)));
}

export function fact(k, v) { return el('div', { class: 'fact' }, el('dt', {}, k), el('dd', {}, v)); }

// Merge a server card (instance) with its definition so name, image and element are always present.
export function full(c) { return Object.assign({}, state.defs[c.def_id] || {}, c); }

// A card as a small clickable tile with name, element, serial and optional price.
export function tile(c, opts = {}) {
  const m = full(c);
  const kids = [
    cardEl(m, { mini: true, badge: opts.badge }),
    el('span', { class: 'cell__name' }, m.name),
    el('span', { class: 'cell__sub' }, cap(m.element) + (m.serial ? ' · #' + m.serial : ''))
  ];
  if (opts.price != null) kids.push(el('span', { class: 'cell__price' }, coin(opts.price)));
  if (opts.note) kids.push(el('span', { class: 'cell__note' }, opts.note));
  const b = el('button', { class: 'cell' + (opts.selected ? ' is-picked' : ''), type: 'button',
    'aria-pressed': opts.selected === undefined ? null : String(Boolean(opts.selected)) }, ...kids);
  b.style.setProperty('--c', rarityColor(m.rarity));
  if (opts.onClick) b.addEventListener('click', () => opts.onClick(m, b));
  return b;
}

export function valueNote(price, value) {
  if (!value) return '';
  const diff = Math.round((price - value) * 100 / value);
  if (Math.abs(diff) < 5) return 'About the same as its reference value.';
  return diff < 0 ? `${-diff}% below its reference value.` : `${diff}% above its reference value.`;
}

export function filterBar(f, onChange, sorts) {
  const mk = (label, key, opts) => {
    const s = el('select', { 'aria-label': label }, opts.map(([v, t]) => el('option', { value: v }, t)));
    s.value = f[key]; s.addEventListener('change', () => { f[key] = s.value; onChange(); });
    return s;
  };
  const q = el('input', { type: 'search', placeholder: 'Search by name', 'aria-label': 'Search' });
  let t; q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { f.q = q.value.trim(); onChange(); }, 300); });
  return el('div', { class: 'filters' }, q,
    mk('Rarity', 'rarity', [['', 'All rarities'], ...state.cat.rarities.map(r => [r.id, r.name])]),
    mk('Element', 'element', [['', 'All elements'], ...ELEMENTS.map(e => [e, cap(e)])]),
    mk('Sort', 'sort', sorts));
}

// A dialog. Returns { close, box }. Esc and a tap outside close it.
export function modal(label, ...kids) {
  const overlay = document.getElementById('overlay');
  const prev = document.activeElement;
  const x = el('button', { class: 'sheet__close', type: 'button', 'aria-label': 'Close' }, '×');
  const box = el('div', { class: 'sheet__panel' }, x, ...kids.flat().filter(Boolean));
  const wrap = el('div', { class: 'sheet', role: 'dialog', 'aria-modal': 'true', 'aria-label': label }, box);
  const onKey = e => { if (e.key === 'Escape') close(); };
  function close() {
    wrap.remove(); document.removeEventListener('keydown', onKey);
    if (!overlay.querySelector('.sheet, .op')) document.body.classList.remove('is-locked');
    if (prev && document.body.contains(prev)) prev.focus({ preventScroll: true });
  }
  x.addEventListener('click', close);
  wrap.addEventListener('click', e => { if (e.target === wrap) close(); });
  overlay.append(wrap); document.body.classList.add('is-locked'); document.addEventListener('keydown', onKey);
  x.focus({ preventScroll: true });
  return { close, box };
}

export function loadingBox() { return el('p', { class: 'loading', role: 'status' }, 'Loading'); }
export function errorBox(msg, retry) {
  const b = el('button', { class: 'btn btn--small', type: 'button' }, 'Try again'); b.addEventListener('click', retry);
  return el('div', { class: 'empty' }, el('p', { class: 'muted' }, msg), b);
}
