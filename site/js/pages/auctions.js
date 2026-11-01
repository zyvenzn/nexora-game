import { rpc, auth } from '../api.js';
import { state, setMe } from '../state.js';
import { el, cardEl, chip, coin, fmt, until, toast, friendly, setTitle } from '../ui.js';
import { marketNav, modal, tile, fact, cap, filterBar, refreshRoute, loadingBox, errorBox } from '../kit.js';

export async function render(ctx) {
  setTitle('Auctions');
  const tab = ctx.params.get('tab') === 'mine' && auth.signedIn ? 'mine' : 'live';
  const clocks = [];
  let ended = false, reload = () => {};
  const timer = setInterval(() => {
    let hit = false;
    for (const c of clocks) { if (c.s.isConnected) { c.upd(); if (c.over()) hit = true; } }
    if (hit && !ended) { ended = true; setTimeout(() => reload(), 1500); }
  }, 1000);
  render.cleanup = () => clearInterval(timer);

  function clock(iso, cls) {
    const s = el('span', { class: cls || 'cell__note' });
    const over = () => new Date(iso).getTime() <= Date.now();
    const upd = () => { s.textContent = over() ? 'Ended' : until(iso) + ' left'; };
    upd(); clocks.push({ s, upd, over });
    return s;
  }
  const bidText = a => (a.bid_count ? `Bid ${coin(a.current_bid)}` : `Starts ${coin(a.start_price)}`);
  function auctionTile(a) {
    const t = tile(a.card, { onClick: () => dialog(a) });
    t.append(el('span', { class: 'cell__price' }, bidText(a)), clock(a.ends_at));
    return t;
  }

  function dialog(a) {
    const c = a.card, signed = auth.signedIn && state.profile;
    const iAmSeller = signed && a.seller.id === state.profile.id;
    const iLead = signed && a.leader && a.leader.id === state.profile.id;
    const err = el('p', { class: 'form__error', role: 'alert' });
    let action = null;
    if (!signed) action = el('a', { class: 'btn btn--wide', href: '#/auth?mode=login' }, 'Log in to bid');
    else if (iAmSeller) {
      if (a.bid_count === 0) {
        action = el('button', { class: 'btn btn--ghost btn--wide', type: 'button' }, 'Cancel auction');
        action.addEventListener('click', async () => {
          action.disabled = true;
          try { await rpc('cancel_auction', { p_id: a.id }); toast('Auction cancelled.'); dlg.close(); refreshRoute(); }
          catch (e) { err.textContent = friendly(e); action.disabled = false; }
        });
      } else action = el('p', { class: 'muted' }, 'Your auction has bids, so it cannot be cancelled.');
    } else {
      const amount = el('input', { type: 'number', min: String(a.min_next_bid), step: '1', inputmode: 'numeric', value: String(a.min_next_bid) });
      const go = el('button', { class: 'btn btn--wide', type: 'button' }, 'Place bid');
      go.addEventListener('click', async () => {
        err.textContent = '';
        const n = Number(amount.value);
        if (!Number.isInteger(n) || n < a.min_next_bid) { err.textContent = friendly({ message: 'bid_too_low' }); return; }
        if (n > state.profile.balance) { err.textContent = friendly({ message: 'insufficient_funds' }); return; }
        go.disabled = true;
        try {
          const r = await rpc('place_bid', { p_id: a.id, p_amount: n });
          setMe(r.me); toast(`You are the highest bidder at ${coin(n)}.`, 'good'); dlg.close(); refreshRoute();
        } catch (e) { err.textContent = friendly(e); go.disabled = false; if (e.message === 'bid_too_low' || e.message === 'auction_ended') setTimeout(() => { dlg.close(); refreshRoute(); }, 1500); }
      });
      action = el('div', { class: 'form' },
        iLead ? el('p', { class: 'banner banner--good' }, 'You are the highest bidder.') : null,
        el('label', { class: 'field' }, el('span', { class: 'field__label' }, 'Your bid'), amount,
          el('span', { class: 'field__hint' }, `Minimum ${coin(a.min_next_bid)}. Your Stardust is held until someone outbids you, then refunded. A bid in the last 2 minutes adds 2 minutes.`)),
        go);
    }
    const dlg = modal(c.name, el('div', { class: 'sheet__body' },
      el('div', { class: 'sheet__card' }, cardEl(c)),
      el('div', { class: 'sheet__info' }, chip(c.rarity), el('h2', {}, c.name),
        el('dl', { class: 'facts' }, fact('Element', cap(c.element)), fact('Serial', '#' + c.serial), fact('Reference value', coin(c.value)),
          fact(a.bid_count ? 'Highest bid' : 'Starting bid', coin(a.bid_count ? a.current_bid : a.start_price)),
          fact('Bids', fmt(a.bid_count)), fact('Time left', clock(a.ends_at, 'time'))),
        el('p', { class: 'small' }, 'Seller: ', el('a', { href: '#/u/' + a.seller.username }, a.seller.display_name),
          a.leader ? [' · Leading: ', el('a', { href: '#/u/' + a.leader.username }, a.leader.display_name)] : null),
        err, action)));
  }

  const root = el('div', { class: 'page' },
    el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, 'Auctions'),
      auth.signedIn ? el('a', { class: 'btn btn--ghost btn--small', href: '#/collection' }, 'Sell from collection') : null),
    marketNav('auctions'),
    el('div', { class: 'seg seg--sub' },
      el('a', { class: 'seg__item' + (tab === 'live' ? ' is-on' : ''), href: '#/auctions' }, 'Live auctions'),
      auth.signedIn ? el('a', { class: 'seg__item' + (tab === 'mine' ? ' is-on' : ''), href: '#/auctions?tab=mine' }, 'My auctions') : null));
  const box = el('div');

  if (tab === 'mine') {
    reload = async () => {
      ended = false; clocks.length = 0; box.replaceChildren(loadingBox());
      try {
        const r = await rpc('my_auctions');
        const sec = (title, list, empty) => el('section', { class: 'section' }, el('h2', { class: 'section__title' }, title),
          list.length ? el('div', { class: 'cgrid cgrid--wide' }, list.map(auctionTile)) : el('p', { class: 'muted' }, empty));
        box.replaceChildren(sec('Bidding on', r.bidding, 'You have no active bids.'), sec('Selling', r.selling, 'You have no running auctions.'));
      } catch (e) { box.replaceChildren(errorBox(friendly(e), reload)); }
    };
    root.append(box);
  } else {
    const f = { q: '', rarity: '', element: '', sort: 'ending' };
    const grid = el('div', { class: 'cgrid cgrid--wide' });
    let seq = 0;
    reload = async () => {
      const my = ++seq; ended = false; clocks.length = 0; grid.replaceChildren(loadingBox());
      try {
        let rows = await rpc('auction_browse', { p_rarity: f.rarity || null, p_element: f.element || null, p_sort: f.sort, p_limit: 60 });
        if (my !== seq) return;
        if (f.q) rows = rows.filter(a => a.card.name.toLowerCase().includes(f.q.toLowerCase()));
        if (!rows.length) { grid.replaceChildren(el('p', { class: 'muted empty' }, 'No live auctions match.')); return; }
        grid.replaceChildren(...rows.map(auctionTile));
      } catch (e) { if (my === seq) grid.replaceChildren(errorBox(friendly(e), reload)); }
    };
    root.append(filterBar(f, reload, [['ending', 'Ending soon'], ['price', 'Highest bid'], ['rarity', 'Rarest first']]), grid);
  }
  await reload();
  return root;
}
