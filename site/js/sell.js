// "Sell" dialog: list a card at a fixed price, or start an auction.
import { rpc } from './api.js';
import { state } from './state.js';
import { el, cardEl, chip, coin, toast, friendly } from './ui.js';
import { modal, fact, cap, full, refreshRoute } from './kit.js';

const HOURS = [1, 6, 12, 24, 48, 72];

export function sellDialog(card) {
  const m = full(card);
  const pct = Number((state.me && state.me.config && state.me.config.fee_pct) || 5);
  let mode = 'fixed';
  const price = el('input', { type: 'number', min: '1', step: '1', inputmode: 'numeric', value: String(m.value || 1) });
  const hours = el('select', { 'aria-label': 'Auction length' }, HOURS.map(h => el('option', { value: String(h) }, h === 1 ? '1 hour' : h + ' hours')));
  hours.value = '24';
  const priceLabel = el('span', { class: 'field__label' }, 'Price');
  const hint = el('span', { class: 'field__hint' });
  const err = el('p', { class: 'form__error', role: 'alert' });
  const go = el('button', { class: 'btn btn--wide', type: 'button' }, 'List for sale');
  const durField = el('label', { class: 'field', hidden: true }, el('span', { class: 'field__label' }, 'Length'), hours);
  const tabF = el('button', { class: 'seg__item is-on', type: 'button' }, 'Fixed price');
  const tabA = el('button', { class: 'seg__item', type: 'button' }, 'Auction');

  const net = () => {
    const p = Math.floor(Number(price.value) || 0);
    const fee = pct <= 0 ? 0 : Math.max(1, Math.floor(p * pct / 100));
    return p > 0 ? p - fee : 0;
  };
  function paint() {
    const a = mode === 'auction';
    tabF.classList.toggle('is-on', !a); tabA.classList.toggle('is-on', a);
    durField.hidden = !a;
    priceLabel.textContent = a ? 'Starting bid' : 'Price';
    go.textContent = a ? 'Start auction' : 'List for sale';
    hint.textContent = `Reference value ${coin(m.value)}. You receive about ${coin(net())} after the ${pct}% fee.` +
      (a ? ' If nobody bids, you get the card back.' : '');
  }
  tabF.addEventListener('click', () => { mode = 'fixed'; paint(); });
  tabA.addEventListener('click', () => { mode = 'auction'; paint(); });
  price.addEventListener('input', paint);

  go.addEventListener('click', async () => {
    err.textContent = '';
    const p = Number(price.value);
    if (!Number.isInteger(p) || p < 1) { err.textContent = friendly({ message: 'bad_price' }); return; }
    go.disabled = true;
    try {
      if (mode === 'fixed') await rpc('list_card', { p_instance: card.id, p_price: p });
      else await rpc('create_auction', { p_instance: card.id, p_start: p, p_hours: Number(hours.value) });
      toast(mode === 'fixed' ? 'Your card is on the marketplace.' : 'Your auction has started.', 'good');
      dlg.close(); refreshRoute();
    } catch (e) { err.textContent = friendly(e); go.disabled = false; }
  });

  const dlg = modal('Sell ' + m.name,
    el('div', { class: 'sheet__body' },
      el('div', { class: 'sheet__card' }, cardEl(m)),
      el('div', { class: 'sheet__info' }, chip(m.rarity), el('h2', {}, m.name),
        el('dl', { class: 'facts' }, fact('Element', cap(m.element)), fact('Serial', '#' + card.serial)),
        el('div', { class: 'seg' }, tabF, tabA),
        el('div', { class: 'form' }, el('label', { class: 'field' }, priceLabel, price, hint), durField, err, go))));
  paint();
  return dlg;
}
