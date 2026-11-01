import { rpc } from '../api.js';
import { state } from '../state.js';
import { el, avatar, chip, fmt, setTitle } from '../ui.js';

const MODES = [['score', 'Collection score'], ['rarest', 'Rarest card'], ['collectors', 'Most cards found']];

export async function render(ctx) {
  setTitle('Leaderboard');
  const mode = MODES.some(m => m[0] === ctx.params.get('by')) ? ctx.params.get('by') : 'score';
  const rows = await rpc('get_leaderboard', { p_limit: 50, p_mode: mode });
  const tabs = el('div', { class: 'seg' }, MODES.map(([k, t]) => el('a', { class: 'seg__item' + (k === mode ? ' is-on' : ''), href: '#/leaderboard?by=' + k }, t)));
  const list = rows.length ? el('ol', { class: 'lb' }, rows.map(r => {
    const me = state.profile && state.profile.username === r.username;
    const row = el('li', { class: 'lb__row' + (me ? ' is-me' : '') },
      el('span', { class: 'lb__pos' }, '#' + r.pos),
      el('a', { class: 'lb__who', href: '#/u/' + r.username }, avatar(r, 40), el('span', { class: 'lb__names' }, el('strong', {}, r.display_name), el('span', { class: 'muted small' }, '@' + r.username))),
      el('span', { class: 'lb__rarest' }, r.rarest ? [chip(r.rarest.rarity), el('span', { class: 'small' }, r.rarest.name + ' #' + r.rarest.serial)] : null),
      el('span', { class: 'lb__score' }, mode === 'collectors' ? fmt(r.unique) + ' found' : fmt(r.score) + ' pts'));
    return row;
  })) : el('p', { class: 'muted empty' }, 'Nobody has opened a pack yet. Be the first.');
  return el('div', { class: 'page' },
    el('div', { class: 'page__head' }, el('h1', { class: 'page-title' }, 'Leaderboard')),
    el('p', { class: 'muted' }, 'Points per card: Common 1, Uncommon 4, Rare 15, Epic 60, Celestial 300.'),
    tabs, list);
}
