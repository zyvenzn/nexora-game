import { rpc } from '../api.js';
import { state } from '../state.js';
import { el, cardEl, chip, coin, fmt, setTitle, rarityColor, rarityName } from '../ui.js';
import { sellDialog } from '../sell.js';

const ELEMENTS = ['celestial', 'ember', 'tide', 'void'];
const cap = s => s[0].toUpperCase() + s.slice(1);

export async function render() {
  setTitle('Collection');
  const [col, prof] = await Promise.all([rpc('my_collection'), rpc('get_public_profile', { p_username: state.profile.username })]);
  const byDef = {};
  col.cards.forEach(c => { (byDef[c.def_id] = byDef[c.def_id] || []).push(c); });
  const defs = state.cat.cards;
  const f = { rarity: 'all', element: 'all', show: 'all', q: '' };

  const root = el('div', { class: 'page' });
  const grid = el('div', { class: 'cgrid' });
  const stats = el('div', { class: 'stats' },
    stat('Cards', fmt(prof.total)), stat('Found', `${prof.unique} / ${defs.length}`),
    stat('Score', fmt(prof.score)), stat('Rank', prof.rank ? '#' + prof.rank : '-'));

  const sel = (label, key, opts) => {
    const s = el('select', { 'aria-label': label }, opts.map(([v, t]) => el('option', { value: v }, t)));
    s.addEventListener('change', () => { f[key] = s.value; draw(); });
    return s;
  };
  const rarSel = sel('Rarity', 'rarity', [['all', 'All rarities'], ...state.cat.rarities.map(r => [r.id, r.name])]);
  const eleSel = sel('Element', 'element', [['all', 'All elements'], ...ELEMENTS.map(e => [e, cap(e)])]);
  const showSel = sel('Show', 'show', [['all', 'All cards'], ['owned', 'Owned'], ['missing', 'Missing']]);
  const q = el('input', { type: 'search', placeholder: 'Search by name', 'aria-label': 'Search cards' });
  q.addEventListener('input', () => { f.q = q.value.trim().toLowerCase(); draw(); });
  const bar = el('div', { class: 'filters' }, q, rarSel, eleSel, showSel);

  function draw() {
    const list = defs.filter(d =>
      (f.rarity === 'all' || d.rarity === f.rarity) && (f.element === 'all' || d.element === f.element) &&
      (!f.q || d.name.toLowerCase().includes(f.q)) &&
      (f.show === 'all' || (f.show === 'owned' ? byDef[d.id] : !byDef[d.id])));
    if (!list.length) { grid.replaceChildren(el('p', { class: 'muted empty' }, 'No cards match these filters.')); return; }
    grid.replaceChildren(...list.map(d => {
      const mine = byDef[d.id] || [];
      const b = el('button', { class: 'cell', type: 'button', 'aria-label': mine.length ? `${d.name}, you own ${mine.length}` : 'Card not found yet' },
        cardEl(d, { mini: true, locked: !mine.length, count: mine.length }),
        el('span', { class: 'cell__name' }, mine.length ? d.name : rarityName(d.rarity)));
      b.style.setProperty('--c', rarityColor(d.rarity));
      b.addEventListener('click', () => sheet(d, mine));
      return b;
    }));
  }

  function sheet(d, mine) {
    const overlay = document.getElementById('overlay');
    const prev = document.activeElement;
    const close = () => { wrap.remove(); document.removeEventListener('keydown', onKey); document.body.classList.remove('is-locked'); if (prev && document.body.contains(prev)) prev.focus({ preventScroll: true }); };
    const onKey = e => { if (e.key === 'Escape') close(); };
    const closeBtn = el('button', { class: 'sheet__close', type: 'button', 'aria-label': 'Close' }, '×');
    closeBtn.addEventListener('click', close);
    const copies = mine.slice().sort((a, b) => a.serial - b.serial);
    const body = el('div', { class: 'sheet__body' },
      el('div', { class: 'sheet__card' }, cardEl(d, { locked: !mine.length })),
      el('div', { class: 'sheet__info' },
        chip(d.rarity),
        el('h2', {}, mine.length ? d.name : 'Not found yet'),
        mine.length ? el('p', { class: 'muted' }, d.blurb) : el('p', { class: 'muted' }, `A ${rarityName(d.rarity)} ${cap(d.element)} card. Open packs to find it.`),
        el('dl', { class: 'facts' },
          fact('Element', cap(d.element)), fact('Reference value', coin(d.value)),
          fact('Lowest price now', d.floor ? coin(d.floor) : 'None for sale'),
          fact('Last sale', d.last_sale ? coin(d.last_sale) : 'No sales yet'),
          fact('Copies in the world', fmt(d.minted)),
          fact('Players who own it', fmt(d.holders))),
        mine.length ? el('div', {}, el('h3', { class: 'small-title' }, `Your copies (${mine.length})`),
          el('ul', { class: 'copies' }, copies.map(c => {
          const li = el('li', {}, '#' + c.serial);
          if (c.status !== 'owned') li.append(el('span', { class: 'tag' }, ({ listed: 'For sale', auction: 'In auction', trade: 'In a trade' })[c.status] || c.status));
          else { const b = el('button', { class: 'linkbtn', type: 'button' }, 'Sell'); b.addEventListener('click', () => { close(); sellDialog(c); }); li.append(b); }
          return li;
        }))) : null));
    const wrap = el('div', { class: 'sheet', role: 'dialog', 'aria-modal': 'true', 'aria-label': d.name }, el('div', { class: 'sheet__panel' }, closeBtn, body));
    wrap.addEventListener('click', e => { if (e.target === wrap) close(); });
    overlay.append(wrap); document.body.classList.add('is-locked'); document.addEventListener('keydown', onKey);
    closeBtn.focus({ preventScroll: true });
  }

  root.append(
    el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, 'Collection'),
      el('a', { class: 'btn btn--ghost btn--small', href: '#/u/' + state.profile.username }, 'Public profile')),
    stats, bar, grid);
  draw();
  return root;
}

function stat(label, value) { return el('div', { class: 'stat' }, el('span', { class: 'stat__v' }, value), el('span', { class: 'stat__l' }, label)); }
function fact(k, v) { return el('div', { class: 'fact' }, el('dt', {}, k), el('dd', {}, v)); }
