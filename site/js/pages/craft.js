import { rpc } from '../api.js';
import { state, setMe } from '../state.js';
import { el, packArt, coin, fmt, toast, friendly, setTitle, rarityName } from '../ui.js';
import { marketNav, modal, tile, loadingBox, errorBox } from '../kit.js';

export async function render() {
  setTitle('Craft');
  const root = el('div', { class: 'page' },
    el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, 'Craft')),
    marketNav('craft'),
    el('p', { class: 'muted' }, 'Trade in spare cards for a new pack. The cards you use are destroyed for good. Cards that are for sale, in an auction or in a trade cannot be used.'));
  const body = el('div');
  root.append(body);

  async function load() {
    body.replaceChildren(loadingBox());
    let col;
    try { col = await rpc('my_collection'); } catch (e) { body.replaceChildren(errorBox(friendly(e), load)); return; }
    const free = col.cards.filter(c => c.status === 'owned');
    body.replaceChildren(...state.cat.recipes.map(r => recipe(r, free)));
  }

  function recipe(r, free) {
    const pack = state.packTypes[r.output_pack];
    const mine = free.filter(c => state.defs[c.def_id] && state.defs[c.def_id].rarity === r.input_rarity);
    const byDef = {};
    mine.forEach(c => { (byDef[c.def_id] = byDef[c.def_id] || []).push(c); });
    Object.values(byDef).forEach(l => l.sort((a, b) => b.serial - a.serial)); // use the highest serials first, keep your low ones
    const pick = {}; // def id -> how many selected
    const total = () => Object.values(pick).reduce((s, n) => s + n, 0);
    const counter = el('p', { class: 'craft__count', 'aria-live': 'polite' });
    const go = el('button', { class: 'btn', type: 'button' }, 'Craft');
    const grid = el('div', { class: 'cgrid cgrid--wide' });

    function paint() {
      const n = total();
      counter.textContent = `${n} / ${r.input_qty} ${rarityName(r.input_rarity)} cards selected (you have ${mine.length})`;
      go.disabled = n !== r.input_qty;
      grid.replaceChildren(...Object.keys(byDef).map(id => {
        const have = byDef[id].length, sel = pick[id] || 0;
        const wrap = el('div', { class: 'stepper' + (sel ? ' is-picked' : '') });
        const minus = el('button', { class: 'btn btn--small btn--ghost', type: 'button', 'aria-label': 'Use one less' }, '−');
        const plus = el('button', { class: 'btn btn--small btn--ghost', type: 'button', 'aria-label': 'Use one more' }, '+');
        minus.disabled = sel <= 0; plus.disabled = sel >= have || total() >= r.input_qty;
        minus.addEventListener('click', () => { pick[id] = sel - 1; paint(); });
        plus.addEventListener('click', () => { pick[id] = sel + 1; paint(); });
        const t = tile({ def_id: id }, { note: `You have ${have}` });
        t.disabled = true; t.classList.add('cell--static');
        wrap.append(t, el('div', { class: 'stepper__row' }, minus, el('span', { class: 'stepper__n' }, `${sel} / ${have}`), plus));
        return wrap;
      }));
    }
    function fill(keepOne) {
      Object.keys(pick).forEach(k => delete pick[k]);
      let left = r.input_qty;
      for (const id of Object.keys(byDef)) { const usable = Math.max(0, byDef[id].length - (keepOne ? 1 : 0)); const n = Math.min(usable, left); if (n) { pick[id] = n; left -= n; } }
      paint();
    }
    const auto1 = el('button', { class: 'btn btn--small btn--ghost', type: 'button' }, 'Use spares (keep one of each)');
    const auto2 = el('button', { class: 'btn btn--small btn--ghost', type: 'button' }, 'Use any');
    const clear = el('button', { class: 'btn btn--small btn--ghost', type: 'button' }, 'Clear');
    auto1.addEventListener('click', () => fill(true)); auto2.addEventListener('click', () => fill(false));
    clear.addEventListener('click', () => { Object.keys(pick).forEach(k => delete pick[k]); paint(); });

    go.addEventListener('click', () => {
      const ids = Object.keys(pick).flatMap(id => byDef[id].slice(0, pick[id]).map(c => c.id));
      const err = el('p', { class: 'form__error', role: 'alert' });
      const yes = el('button', { class: 'btn btn--wide', type: 'button' }, `Destroy ${ids.length} cards and craft`);
      const no = el('button', { class: 'btn btn--ghost btn--wide', type: 'button' }, 'Go back');
      const dlg = modal('Confirm craft', el('div', { class: 'form' },
        el('h2', {}, 'Craft a ' + pack.name + '?'),
        el('p', {}, `${ids.length} ${rarityName(r.input_rarity)} cards will be destroyed. This cannot be undone.`), err, yes, no));
      no.addEventListener('click', () => dlg.close());
      yes.addEventListener('click', async () => {
        yes.disabled = true;
        try {
          const res = await rpc('craft_pack', { p_recipe: r.id, p_ids: ids });
          setMe(res.me); dlg.close(); toast(`Crafted a ${pack.name}. Open it from Packs.`, 'good'); location.hash = '#/packs';
        } catch (e) { err.textContent = friendly(e); yes.disabled = false; }
      });
    });

    paint();
    return el('section', { class: 'panel' },
      el('div', { class: 'craft__head' }, el('div', { class: 'craft__art' }, packArt(pack)),
        el('div', {}, el('h2', {}, r.name), el('p', { class: 'muted' }, `${r.input_qty} ${rarityName(r.input_rarity)} cards make 1 ${pack.name}.`), counter)),
      mine.length < r.input_qty ? el('p', { class: 'muted' }, `You need ${r.input_qty - mine.length} more ${rarityName(r.input_rarity)} cards.`) : null,
      mine.length ? el('div', { class: 'craft__tools' }, auto1, auto2, clear) : null,
      grid, el('div', { class: 'craft__go' }, go));
  }
  await load();
  return root;
}
