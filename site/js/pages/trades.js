import { rpc } from '../api.js';
import { state, setMe } from '../state.js';
import { el, avatar, coin, fmt, ago, until, toast, friendly, setTitle } from '../ui.js';
import { marketNav, modal, tile, full, refreshRoute, loadingBox, errorBox } from '../kit.js';

const STATUS = { pending: 'Waiting', accepted: 'Completed', declined: 'Declined', cancelled: 'Cancelled', expired: 'Expired' };
const plural = n => `${n} card${n === 1 ? '' : 's'}`;
const describe = (cards, coins) => {
  const parts = [];
  if (cards.length) parts.push(plural(cards.length));
  if (coins > 0) parts.push(coin(coins));
  return parts.length ? parts.join(' + ') : 'nothing';
};
// Everything from the viewer's point of view.
function sides(t) {
  const out = t.direction === 'out';
  return {
    other: out ? t.to : t.from,
    giveCards: out ? t.give : t.want, giveCoins: out ? t.give_coins : t.want_coins, giveValue: out ? t.give_value : t.want_value,
    getCards: out ? t.want : t.give, getCoins: out ? t.want_coins : t.give_coins, getValue: out ? t.want_value : t.give_value
  };
}

export async function render(ctx) {
  if (ctx.arg === 'new') return composer(ctx);
  if (ctx.arg) return detail(ctx.arg);
  return list();
}

/* ------------------------------------------------------------------ list */
async function list() {
  setTitle('Trades');
  const root = el('div', { class: 'page' },
    el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, 'Trades'), el('a', { class: 'btn btn--small', href: '#/trades/new' }, 'New trade')),
    marketNav('trades'),
    el('p', { class: 'muted' }, 'Trades are safe: the sender’s cards and Stardust are held until the other player answers, and an offer cannot be changed once sent.'));
  const body = el('div'); root.append(body);
  async function load() {
    body.replaceChildren(loadingBox());
    try {
      const r = await rpc('my_trades');
      const inbox = r.pending.filter(t => t.direction === 'in'), outbox = r.pending.filter(t => t.direction === 'out');
      const sec = (title, arr, empty) => el('section', { class: 'section' }, el('h2', { class: 'section__title' }, title),
        arr.length ? el('div', { class: 'tradelist' }, arr.map(card)) : el('p', { class: 'muted' }, empty));
      body.replaceChildren(sec('Waiting for your answer', inbox, 'No offers for you right now.'), sec('Your offers', outbox, 'You have no open offers.'), sec('Recent history', r.history, 'Nothing yet.'));
    } catch (e) { body.replaceChildren(errorBox(friendly(e), load)); }
  }
  function card(t) {
    const s = sides(t);
    return el('a', { class: 'tradecard' + (t.unfair ? ' is-warn' : ''), href: '#/trades/' + t.id },
      avatar(s.other, 44),
      el('span', { class: 'tradecard__main' },
        el('strong', {}, (t.direction === 'out' ? 'To @' : 'From @') + s.other.username),
        el('span', { class: 'small' }, `You give ${describe(s.giveCards, s.giveCoins)}, you get ${describe(s.getCards, s.getCoins)}`),
        el('span', { class: 'muted small' }, t.status === 'pending' ? `Expires in ${until(t.expires_at)}` : ago(t.resolved_at || t.created_at))),
      el('span', { class: 'tag' + (t.status === 'pending' ? '' : ' tag--quiet') }, STATUS[t.status] || t.status),
      t.unfair ? el('span', { class: 'tag tag--bad' }, 'Uneven') : null);
  }
  await load();
  return root;
}

/* ---------------------------------------------------------------- detail */
async function detail(id) {
  setTitle('Trade');
  const root = el('div', { class: 'page page--narrow' });
  async function load() {
    root.replaceChildren(loadingBox());
    let t;
    try { t = await rpc('get_trade', { p_id: id }); }
    catch (e) { root.replaceChildren(el('a', { class: 'linkbtn', href: '#/trades' }, '← All trades'), errorBox(friendly(e), load)); return; }
    const s = sides(t), pending = t.status === 'pending';
    const side = (title, cards, coins, value) => el('section', { class: 'side' },
      el('h2', {}, title), cards.length ? el('div', { class: 'cgrid cgrid--small' }, cards.map(c => tile(c, { price: c.value }))) : null,
      coins > 0 ? el('p', { class: 'side__coins' }, coin(coins) + ' Stardust') : null,
      !cards.length && !(coins > 0) ? el('p', { class: 'muted' }, 'Nothing') : null,
      el('p', { class: 'muted small' }, 'Total value ' + coin(value)));
    const warns = [];
    if (pending && t.unfair) warns.push(el('p', { class: 'banner banner--warn' }, `This trade is very uneven for you: you give ${coin(s.giveValue)} of value and get ${coin(s.getValue)}. Think twice.`));
    if (pending && t.partner) {
      if (t.partner.age_days < 3) warns.push(el('p', { class: 'banner banner--warn' }, `@${s.other.username} joined ${t.partner.age_days < 1 ? 'today' : t.partner.age_days + ' day(s) ago'}. Be careful with new accounts.`));
      if (t.partner.reports_open > 0) warns.push(el('p', { class: 'banner banner--warn' }, `@${s.other.username} has been reported ${t.partner.reports_open} time(s).`));
    }
    const actions = el('div', { class: 'actions' });
    if (pending && t.direction === 'in') {
      const a = el('button', { class: 'btn', type: 'button' }, 'Accept'), d = el('button', { class: 'btn btn--ghost', type: 'button' }, 'Decline');
      a.addEventListener('click', () => acceptDialog(t, s));
      d.addEventListener('click', async () => { d.disabled = true; try { await rpc('decline_trade', { p_id: t.id }); toast('Offer declined.'); load(); } catch (e) { toast(friendly(e), 'error'); load(); } });
      actions.append(a, d);
    } else if (pending) {
      const c = el('button', { class: 'btn btn--ghost', type: 'button' }, 'Cancel offer');
      c.addEventListener('click', async () => { c.disabled = true; try { const r = await rpc('cancel_trade', { p_id: t.id }); setMe(r.me); toast('Offer cancelled. Your cards and Stardust are back.', 'good'); load(); } catch (e) { toast(friendly(e), 'error'); load(); } });
      actions.append(c);
    }
    const rep = el('button', { class: 'linkbtn', type: 'button' }, `Report @${s.other.username}`);
    rep.addEventListener('click', () => reportDialog(s.other, t.id));
    root.replaceChildren(
      el('a', { class: 'linkbtn', href: '#/trades' }, '← All trades'),
      el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, t.direction === 'out' ? 'Your offer' : 'Offer for you'),
        el('span', { class: 'tag' }, STATUS[t.status] || t.status)),
      el('p', {}, avatar(s.other, 28), ' ', el('a', { href: '#/u/' + s.other.username }, s.other.display_name), el('span', { class: 'muted' }, ' @' + s.other.username),
        t.partner ? el('span', { class: 'muted small' }, ` · ${fmt(t.partner.trades_done)} trades done`) : null),
      t.message ? el('p', { class: 'quote' }, '“' + t.message + '”') : null,
      ...warns,
      side('You give', s.giveCards, s.giveCoins, s.giveValue),
      side('You get', s.getCards, s.getCoins, s.getValue),
      pending ? el('p', { class: 'muted small' }, `Expires in ${until(t.expires_at)}. Nothing changes until it is accepted.`) : null,
      actions,
      el('details', { class: 'odds' }, el('summary', {}, 'Staying safe'),
        el('ul', { class: 'tips' }, [
          'Compare the total values. Reference values come from real sales in the game.',
          'Check serial numbers. Low numbers are worth more to collectors.',
          'Nobody can change an offer after it is sent, and the sender’s items are already held.',
          'Never trade outside the game or share your password. Staff will never ask for it.'].map(x => el('li', {}, x)))),
      rep);
  }
  function acceptDialog(t, s) {
    const err = el('p', { class: 'form__error', role: 'alert' });
    const ok = el('button', { class: 'btn btn--wide', type: 'button' }, 'Accept trade');
    const chk = el('input', { type: 'checkbox' });
    if (t.unfair) ok.disabled = true;
    chk.addEventListener('change', () => { ok.disabled = !chk.checked; });
    const dlg = modal('Confirm trade', el('div', { class: 'form' },
      el('h2', {}, 'Accept this trade?'),
      el('p', {}, `You give ${describe(s.giveCards, s.giveCoins)} and get ${describe(s.getCards, s.getCoins)}.`),
      t.unfair ? el('label', { class: 'check' }, chk, ' I understand this trade is very uneven for me.') : null,
      err, ok));
    ok.addEventListener('click', async () => {
      ok.disabled = true;
      try { const r = await rpc('accept_trade', { p_id: t.id }); setMe(r.me); dlg.close(); toast('Trade complete.', 'good'); load(); }
      catch (e) { err.textContent = friendly(e); ok.disabled = false; }
    });
  }
  await load();
  return root;
}

function reportDialog(user, tradeId) {
  const reason = el('textarea', { rows: '3', maxlength: '300', placeholder: 'What happened?' });
  const err = el('p', { class: 'form__error', role: 'alert' });
  const go = el('button', { class: 'btn btn--wide', type: 'button' }, 'Send report');
  const dlg = modal('Report player', el('div', { class: 'form' }, el('h2', {}, 'Report @' + user.username),
    el('label', { class: 'field' }, el('span', { class: 'field__label' }, 'Reason'), reason), err, go));
  go.addEventListener('click', async () => {
    go.disabled = true;
    try { await rpc('report_user', { p_username: user.username, p_reason: reason.value, p_trade: tradeId || null }); dlg.close(); toast('Report sent. Thank you.', 'good'); }
    catch (e) { err.textContent = friendly(e); go.disabled = false; }
  });
}

/* -------------------------------------------------------------- composer */
async function composer(ctx) {
  setTitle('New trade');
  const give = new Set(), want = new Set();
  let theirs = [], mine = [], target = '';
  const root = el('div', { class: 'page' },
    el('a', { class: 'linkbtn', href: '#/trades' }, '← All trades'),
    el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, 'New trade')));
  const who = el('input', { type: 'text', maxlength: '20', autocapitalize: 'none', spellcheck: 'false', placeholder: 'their username', value: ctx.params.get('to') || '' });
  const loadBtn = el('button', { class: 'btn', type: 'button' }, 'Load cards');
  const whoErr = el('p', { class: 'form__error', role: 'alert' });
  root.append(el('div', { class: 'panel' }, el('label', { class: 'field' }, el('span', { class: 'field__label' }, 'Trade with'), who), whoErr, loadBtn));
  const work = el('div'); root.append(work);

  async function loadPlayer() {
    whoErr.textContent = ''; loadBtn.disabled = true;
    try {
      const name = who.value.trim().replace(/^@/, '');
      const [t, col] = await Promise.all([rpc('player_cards', { p_username: name }), rpc('my_collection')]);
      theirs = t; mine = col.cards.filter(c => c.status === 'owned'); target = name.toLowerCase();
      give.clear(); want.clear(); draw();
    } catch (e) { whoErr.textContent = friendly(e); work.replaceChildren(); }
    loadBtn.disabled = false;
  }
  loadBtn.addEventListener('click', loadPlayer);

  function draw() {
    const gCoins = el('input', { type: 'number', min: '0', step: '1', inputmode: 'numeric', value: '0' });
    const wCoins = el('input', { type: 'number', min: '0', step: '1', inputmode: 'numeric', value: '0' });
    const msg = el('input', { type: 'text', maxlength: '140', placeholder: 'Optional message' });
    const sum = el('div', { class: 'tradesum', 'aria-live': 'polite' });
    const err = el('p', { class: 'form__error', role: 'alert' });
    const send = el('button', { class: 'btn btn--wide', type: 'button' }, 'Send offer');
    const val = (set, arr) => arr.filter(c => set.has(c.id)).reduce((s, c) => s + (full(c).value || 0), 0);
    const nums = () => [Math.max(0, Math.floor(Number(gCoins.value) || 0)), Math.max(0, Math.floor(Number(wCoins.value) || 0))];
    function recalc() {
      const [gc, wc] = nums();
      const gv = val(give, mine) + gc, wv = val(want, theirs) + wc;
      sum.replaceChildren(el('p', {}, `You give ${describe([...give], gc)} (value ${coin(gv)})`), el('p', {}, `You get ${describe([...want], wc)} (value ${coin(wv)})`),
        gv > 0 && wv * 2 < gv ? el('p', { class: 'banner banner--warn' }, 'You are giving much more than you get. Is that what you want?') : null);
      send.disabled = give.size + want.size + gc + wc === 0;
    }
    const picker = (title, arr, set) => {
      const grid = el('div', { class: 'cgrid cgrid--small' });
      const paint = () => grid.replaceChildren(...arr.map(c => tile(c, { selected: set.has(c.id), price: full(c).value, onClick: () => {
        if (set.has(c.id)) set.delete(c.id); else if (set.size < 12) set.add(c.id); else { toast('Up to 12 cards per side.', 'error'); return; }
        paint(); recalc();
      } })));
      paint();
      return el('section', { class: 'side' }, el('h2', {}, title), arr.length ? grid : el('p', { class: 'muted' }, 'No cards available.'));
    };
    [gCoins, wCoins].forEach(i => i.addEventListener('input', recalc));
    send.addEventListener('click', async () => {
      err.textContent = ''; const [gc, wc] = nums();
      if (gc > state.profile.balance) { err.textContent = friendly({ message: 'insufficient_funds' }); return; }
      send.disabled = true;
      try {
        const r = await rpc('create_trade', { p_to: target, p_give: [...give], p_want: [...want], p_give_coins: gc, p_want_coins: wc, p_message: msg.value });
        setMe(await rpc('get_me'));
        toast('Offer sent.', 'good'); location.hash = '#/trades/' + r.trade_id;
      } catch (e) { err.textContent = friendly(e); send.disabled = false; }
    });
    work.replaceChildren(
      picker('Cards you give', mine, give),
      el('label', { class: 'field' }, el('span', { class: 'field__label' }, 'Stardust you give (held until they answer)'), gCoins),
      picker(`Cards you want from @${target}`, theirs, want),
      el('label', { class: 'field' }, el('span', { class: 'field__label' }, 'Stardust you ask for'), wCoins),
      el('label', { class: 'field' }, el('span', { class: 'field__label' }, 'Message'), msg),
      sum, err, send);
    recalc();
  }
  if (who.value) await loadPlayer();
  return root;
}
