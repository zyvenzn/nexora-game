import { rpc, auth } from '../api.js';
import { state, setMe } from '../state.js';
import { el, cardEl, chip, coin, ago, toast, friendly, setTitle } from '../ui.js';
import { marketNav, modal, tile, fact, cap, valueNote, filterBar, refreshRoute, loadingBox, errorBox } from '../kit.js';

export async function render(ctx) {
  setTitle('Marketplace');
  const mine = ctx.params.get('tab') === 'mine' && auth.signedIn;
  const root = el('div', { class: 'page' },
    el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, 'Marketplace'),
      auth.signedIn ? el('a', { class: 'btn btn--ghost btn--small', href: '#/collection' }, 'Sell from collection') : null),
    marketNav('market'),
    el('div', { class: 'seg seg--sub' },
      el('a', { class: 'seg__item' + (mine ? '' : ' is-on'), href: '#/market' }, 'Browse'),
      auth.signedIn ? el('a', { class: 'seg__item' + (mine ? ' is-on' : ''), href: '#/market?tab=mine' }, 'My listings') : null));
  const grid = el('div', { class: 'cgrid cgrid--wide' });

  if (mine) {
    root.append(grid);
    const load = async () => {
      grid.replaceChildren(loadingBox());
      try {
        const rows = await rpc('my_listings');
        if (!rows.length) { grid.replaceChildren(el('p', { class: 'muted empty' }, 'You have nothing for sale. Open a card in your collection and press Sell.')); return; }
        grid.replaceChildren(...rows.map(r => tile(r.card, { price: r.price, onClick: () => mineDialog(r) })));
      } catch (e) { grid.replaceChildren(errorBox(friendly(e), load)); }
    };
    await load();
    return root;
  }

  const f = { q: '', rarity: '', element: '', sort: 'new' };
  let seq = 0;
  const load = async () => {
    const my = ++seq;
    grid.replaceChildren(loadingBox());
    try {
      const rows = await rpc('market_browse', { p_rarity: f.rarity || null, p_element: f.element || null, p_search: f.q || null, p_sort: f.sort, p_limit: 60 });
      if (my !== seq) return;
      if (!rows.length) { grid.replaceChildren(el('p', { class: 'muted empty' }, 'No cards for sale match these filters.')); return; }
      grid.replaceChildren(...rows.map(r => tile(r.card, { price: r.price, note: 'by ' + r.seller.display_name, onClick: () => buyDialog(r) })));
    } catch (e) { if (my === seq) grid.replaceChildren(errorBox(friendly(e), load)); }
  };
  root.append(filterBar(f, load, [['new', 'Newest'], ['price_asc', 'Price: low to high'], ['price_desc', 'Price: high to low'], ['rarity', 'Rarest first']]), grid);
  await load();
  return root;
}

function buyDialog(row) {
  const c = row.card;
  const signed = auth.signedIn && state.profile;
  const mineRow = signed && row.seller.id === state.profile.id;
  const err = el('p', { class: 'form__error', role: 'alert' });
  let action;
  if (!signed) action = el('a', { class: 'btn btn--wide', href: '#/auth?mode=login' }, 'Log in to buy');
  else if (mineRow) action = el('p', { class: 'muted' }, 'This is your listing. Cancel it from My listings.');
  else {
    action = el('button', { class: 'btn btn--wide', type: 'button' }, `Buy for ${coin(row.price)}`);
    if (state.profile.balance < row.price) { action.disabled = true; err.textContent = friendly({ message: 'insufficient_funds' }); }
    action.addEventListener('click', async () => {
      action.disabled = true; err.textContent = '';
      try {
        const r = await rpc('buy_listing', { p_id: row.id, p_expected: row.price });
        setMe(r.me);
        toast(`You bought ${c.name} #${c.serial}.`, 'good');
        dlg.close(); refreshRoute();
      } catch (e) {
        err.textContent = friendly(e);
        if (e.message === 'price_changed' || e.message === 'listing_gone') setTimeout(() => { dlg.close(); refreshRoute(); }, 1500);
        else action.disabled = false;
      }
    });
  }
  const dlg = modal(c.name, el('div', { class: 'sheet__body' },
    el('div', { class: 'sheet__card' }, cardEl(c)),
    el('div', { class: 'sheet__info' }, chip(c.rarity), el('h2', {}, c.name),
      el('p', { class: 'muted' }, c.blurb),
      el('dl', { class: 'facts' }, fact('Element', cap(c.element)), fact('Serial', '#' + c.serial),
        fact('Reference value', coin(c.value)), fact('Price', coin(row.price)), fact('Listed', ago(row.created_at))),
      el('p', { class: 'small muted' }, valueNote(row.price, c.value)),
      el('p', { class: 'small' }, 'Seller: ', el('a', { href: '#/u/' + row.seller.username }, row.seller.display_name)),
      err, action)));
}

function mineDialog(r) {
  const c = r.card;
  const b = el('button', { class: 'btn btn--ghost btn--wide', type: 'button' }, 'Cancel listing');
  const err = el('p', { class: 'form__error', role: 'alert' });
  b.addEventListener('click', async () => {
    b.disabled = true;
    try { await rpc('cancel_listing', { p_id: r.id }); toast('Listing cancelled.'); dlg.close(); refreshRoute(); }
    catch (e) { err.textContent = friendly(e); b.disabled = false; }
  });
  const dlg = modal(c.name, el('div', { class: 'sheet__body' },
    el('div', { class: 'sheet__card' }, cardEl(c)),
    el('div', { class: 'sheet__info' }, chip(c.rarity), el('h2', {}, c.name),
      el('dl', { class: 'facts' }, fact('Your price', coin(r.price)), fact('Reference value', coin(c.value)), fact('Listed', ago(r.created_at))),
      err, b)));
}
