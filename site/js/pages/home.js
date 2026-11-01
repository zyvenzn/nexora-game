import { rpc, auth } from '../api.js';
import { state } from '../state.js';
import { el, packArt, cardEl, chip, avatar, coin, fmt, ago, setTitle } from '../ui.js';

function feedLine(f) {
  const who = f.user ? f.user.display_name : 'Someone';
  const p = f.payload || {};
  if (f.kind === 'pull') return [el('a', { href: '#/u/' + f.user.username }, who), ' pulled ', chip(p.rarity), ' ', p.name];
  if (f.kind === 'sale') return [el('a', { href: '#/u/' + f.user.username }, who), ' bought ', p.name, ' for ', coin(p.price)];
  if (f.kind === 'auction') return [el('a', { href: '#/u/' + f.user.username }, who), ' won ', p.name, ' for ', coin(p.price)];
  return [who, ' did something'];
}

export async function render() {
  setTitle('');
  const [feed, top] = await Promise.all([rpc('feed_recent', { p_limit: 8 }), rpc('get_leaderboard', { p_limit: 5, p_mode: 'score' })]);
  const signed = auth.signedIn && state.profile;
  const featured = state.cat.cards.filter(c => c.rarity !== 'common').slice(0, 1).concat(state.cat.cards.slice(0, 2)).slice(0, 3);
  const starter = state.packTypes.starter || state.cat.packs[0];

  const hero = el('section', { class: 'hero' },
    el('div', { class: 'hero__text' },
      el('h1', { class: 'hero__title' }, 'Tiny dragons. Big pulls.'),
      el('p', { class: 'hero__lead' }, 'Open packs, flip your cards, and build a collection of pixel dragons. Trade with friends and climb the leaderboard. It is free and uses play money only.'),
      el('div', { class: 'hero__cta' },
        signed ? el('a', { class: 'btn', href: '#/packs' }, 'Open packs') : el('a', { class: 'btn', href: '#/auth?mode=signup' }, 'Play free'),
        signed ? el('a', { class: 'btn btn--ghost', href: '#/collection' }, 'My collection') : el('a', { class: 'btn btn--ghost', href: '#/auth?mode=login' }, 'Log in'))),
    el('div', { class: 'hero__art', 'aria-hidden': 'true' }, starter ? packArt(starter) : null));

  const dash = signed ? el('section', { class: 'panel panel--row' },
    el('div', {}, el('h2', {}, 'Welcome back, ' + state.profile.display_name),
      el('p', { class: 'muted' }, `${coin(state.profile.balance)} Stardust, ${Object.values(state.packs).reduce((a, b) => a + b, 0)} unopened pack(s).`)),
    el('a', { class: 'btn', href: '#/packs' }, 'Go to packs')) : null;

  const cards = el('section', { class: 'section' }, el('h2', { class: 'section__title' }, 'Meet some of the cards'),
    el('div', { class: 'showcase' }, featured.map(c => el('figure', { class: 'showcase__item' }, cardEl(c, { mini: true }), el('figcaption', {}, c.name)))));

  const feedBox = el('section', { class: 'section' }, el('h2', { class: 'section__title' }, 'Recent activity'),
    feed.length ? el('ul', { class: 'feed' }, feed.map(f => el('li', { class: 'feed__item' }, el('span', {}, feedLine(f)), el('span', { class: 'muted small' }, ago(f.at)))))
      : el('p', { class: 'muted' }, 'Quiet for now. Open a pack and start the feed.'));

  const lb = el('section', { class: 'section' }, el('h2', { class: 'section__title' }, 'Top collectors'),
    top.length ? el('ol', { class: 'lb' }, top.map(r => el('li', { class: 'lb__row' },
      el('span', { class: 'lb__pos' }, '#' + r.pos),
      el('a', { class: 'lb__who', href: '#/u/' + r.username }, avatar(r, 40), el('span', { class: 'lb__names' }, el('strong', {}, r.display_name), el('span', { class: 'muted small' }, '@' + r.username))),
      el('span', { class: 'lb__rarest' }),
      el('span', { class: 'lb__score' }, fmt(r.score) + ' pts'))))
      : el('p', { class: 'muted' }, 'No collectors yet.'),
    el('a', { class: 'linkbtn', href: '#/leaderboard' }, 'Full leaderboard'));

  return el('div', { class: 'page' }, hero, dash, cards, el('div', { class: 'two' }, feedBox, lb));
}
