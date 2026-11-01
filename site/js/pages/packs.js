import { rpc } from '../api.js';
import { state, setMe } from '../state.js';
import { el, packArt, coin, fmt, until, toast, friendly, setTitle, rarityName, rarityColor } from '../ui.js';
import { openPack } from '../opener.js';

function oddsTable(p) {
  const total = Object.values(p.odds).reduce((s, v) => s + Number(v), 0) || 1;
  // only show rarities that exist in the game right now, rescaled to 100%
  const live = state.cat.rarities.filter(r => state.cat.cards.some(c => c.rarity === r.id) && Number(p.odds[r.id]) > 0);
  const liveTotal = live.reduce((s, r) => s + Number(p.odds[r.id]), 0) || total;
  const rows = live.map(r => {
    const pct = 100 * Number(p.odds[r.id]) / liveTotal;
    const row = el('li', { class: 'odds__row' }, el('span', { class: 'odds__name' }, r.name), el('span', { class: 'odds__pct' }, (pct >= 10 ? pct.toFixed(0) : pct.toFixed(1)) + '%'));
    row.style.setProperty('--c', r.color);
    return row;
  });
  const note = [];
  if (p.element) note.push(`${p.element[0].toUpperCase() + p.element.slice(1)} cards are about 3x more likely.`);
  if (p.guarantee_rarity) note.push(`The last card is ${rarityName(p.guarantee_rarity)} or better.`);
  return el('details', { class: 'odds' }, el('summary', {}, 'See the odds'),
    el('ul', { class: 'odds__list' }, rows),
    el('p', { class: 'muted small' }, 'Per card, based on the cards that exist today. Higher rarities appear as they are added. ' + note.join(' ')));
}

export async function render() {
  setTitle('Packs');
  const root = el('div', { class: 'page' });

  async function refresh() {
    const me = await rpc('get_me');
    setMe(me);
    draw();
  }

  async function open(packId, btn) {
    btn.disabled = true;
    const r = await openPack(packId);
    if (r === 'again') { await open(packId, btn); return; }
    await refresh();
  }

  async function buy(p, qty, btn) {
    btn.disabled = true;
    try {
      const me = await rpc('buy_pack', { p_pack: p.id, p_qty: qty });
      setMe(me);
      toast(`Bought ${qty} ${p.name}${qty > 1 ? 's' : ''}.`, 'good');
    } catch (e) { toast(friendly(e), 'error'); }
    draw();
  }

  async function daily(btn) {
    btn.disabled = true;
    try {
      const me = await rpc('claim_daily');
      setMe(me);
      toast(`Daily bonus: +${fmt(state.me.config.daily_bonus)} Stardust.`, 'good');
    } catch (e) { toast(friendly(e), 'error'); }
    draw();
  }

  function draw() {
    const prof = state.profile;
    const inv = state.cat.packs.filter(p => (state.packs[p.id] || 0) > 0);
    const shop = state.cat.packs.filter(p => p.purchasable);
    root.replaceChildren(
      el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, 'Packs'), el('p', { class: 'balance-big' }, coin(prof.balance))),

      // daily bonus
      (() => {
        const next = prof.next_daily_at ? new Date(prof.next_daily_at) : null;
        const ready = !next || next.getTime() <= Date.now();
        const b = el('button', { class: 'btn', type: 'button' }, ready ? `Claim ${fmt(state.me.config.daily_bonus)} Stardust` : `Ready in ${until(prof.next_daily_at)}`);
        b.disabled = !ready;
        b.addEventListener('click', () => daily(b));
        return el('section', { class: 'panel panel--row' }, el('div', {}, el('h2', {}, 'Daily bonus'), el('p', { class: 'muted' }, 'Free Stardust every day, enough to keep opening packs.')), b);
      })(),

      el('section', { class: 'panel panel--row' }, el('div', {}, el('h2', {}, 'Craft packs'), el('p', { class: 'muted' }, 'Turn spare cards into new packs.')), el('a', { class: 'btn btn--ghost', href: '#/craft' }, 'Open crafting')),

      // owned, unopened packs
      el('section', { class: 'section' },
        el('h2', { class: 'section__title' }, 'Your packs'),
        inv.length === 0
          ? el('p', { class: 'muted' }, 'No unopened packs. Buy one below, or craft one from your collection.')
          : el('div', { class: 'shelf' }, inv.map(p => {
              const b = el('button', { class: 'btn', type: 'button' }, `Open (${state.packs[p.id]})`);
              b.addEventListener('click', () => open(p.id, b));
              return el('div', { class: 'shelf__item' }, el('div', { class: 'shelf__art' }, packArt(p)), el('h3', {}, p.name), b);
            }))),

      // shop
      el('section', { class: 'section' },
        el('h2', { class: 'section__title' }, 'Shop'),
        el('div', { class: 'shop' }, shop.map(p => {
          const one = el('button', { class: 'btn', type: 'button' }, `Buy 1 · ${coin(p.price)}`);
          const five = el('button', { class: 'btn btn--ghost', type: 'button' }, `Buy 5 · ${coin(p.price * 5)}`);
          one.disabled = prof.balance < p.price; five.disabled = prof.balance < p.price * 5;
          one.addEventListener('click', () => buy(p, 1, one));
          five.addEventListener('click', () => buy(p, 5, five));
          return el('article', { class: 'shop__item' },
            el('div', { class: 'shop__art' }, packArt(p)),
            el('div', { class: 'shop__info' }, el('h3', {}, p.name), el('p', { class: 'muted' }, p.description),
              el('p', { class: 'small' }, `${p.cards_count} cards per pack`), oddsTable(p),
              el('div', { class: 'shop__buy' }, one, five)));
        }))));
  }

  const timer = setInterval(() => { if (document.body.contains(root) && state.profile && state.profile.next_daily_at && new Date(state.profile.next_daily_at) > new Date()) draw(); }, 30000);
  render.cleanup = () => clearInterval(timer);
  draw();
  return root;
}
