import { rpc } from '../api.js';
import { state } from '../state.js';
import { el, cardEl, chip, avatar, coin, fmt, setTitle } from '../ui.js';

export async function render(ctx) {
  let p;
  try { p = await rpc('get_public_profile', { p_username: ctx.arg || '' }); }
  catch (e) {
    setTitle('Player not found');
    return el('div', { class: 'page' }, el('h1', { class: 'page-title' }, 'Player not found'), el('p', { class: 'muted' }, 'Check the username and try again.'), el('a', { class: 'btn', href: '#/leaderboard' }, 'See the leaderboard'));
  }
  setTitle(p.display_name);
  const mine = state.profile && state.profile.username === p.username;
  const joined = new Date(p.created_at).toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
  const banner = el('div', { class: 'pf__banner' }, p.banner_url ? el('img', { src: p.banner_url, alt: '' }) : null);
  const head = el('header', { class: 'pf__head' },
    avatar(p, 88),
    el('div', { class: 'pf__names' }, el('h1', { class: 'page-title' }, p.display_name), el('p', { class: 'muted' }, '@' + p.username + ' · joined ' + joined),
      p.banned ? el('p', { class: 'tag tag--bad' }, 'Suspended') : null),
    mine ? el('a', { class: 'btn btn--ghost btn--small', href: '#/settings' }, 'Edit profile') : null);
  const stats = el('div', { class: 'stats' },
    s('Rank', p.rank ? '#' + p.rank : '-'), s('Score', fmt(p.score)), s('Cards', fmt(p.total)), s('Completion', p.completion + '%'), s('Trades', fmt(p.trades_done)));
  return el('div', { class: 'page pf' }, banner, head,
    p.bio ? el('p', { class: 'pf__bio' }, p.bio) : null, stats,
    el('section', { class: 'section' }, el('h2', { class: 'section__title' }, 'Showcase'),
      p.showcase.length
        ? el('div', { class: 'showcase' }, p.showcase.map(c => el('figure', { class: 'showcase__item' }, cardEl(c, { mini: true }), el('figcaption', {}, c.name, el('span', { class: 'muted' }, ' #' + c.serial)))))
        : el('p', { class: 'muted' }, 'No cards yet.')));
}
function s(l, v) { return el('div', { class: 'stat' }, el('span', { class: 'stat__v' }, v), el('span', { class: 'stat__l' }, l)); }
