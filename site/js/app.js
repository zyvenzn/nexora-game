import { configured, auth, rpc } from './api.js';
import { state, setCatalog, setMe, clearMe, subscribe } from './state.js';
import { el, emblem, coin, avatar, toast, friendly } from './ui.js';

const ROUTES = {
  '': { load: () => import('./pages/home.js') },
  'auth': { load: () => import('./pages/auth.js') },
  'welcome': { load: () => import('./pages/auth.js'), fn: 'renderWelcome' },
  'packs': { load: () => import('./pages/packs.js'), need: true },
  'collection': { load: () => import('./pages/collection.js'), need: true },
  'settings': { load: () => import('./pages/settings.js'), need: true },
  'leaderboard': { load: () => import('./pages/leaderboard.js') },
  'u': { load: () => import('./pages/profile.js') }
};
const NAV = [['', 'Home'], ['packs', 'Packs'], ['collection', 'Collection'], ['leaderboard', 'Ranks']];

const view = document.getElementById('view');
let current = null, seq = 0;

function parse() {
  const raw = location.hash.replace(/^#\/?/, '');
  const [path, query = ''] = raw.split('?');
  const parts = path.split('/').filter(Boolean).map(decodeURIComponent);
  return { name: parts[0] || '', arg: parts[1] || '', params: new URLSearchParams(query) };
}

function chrome() {
  const r = parse(), signed = auth.signedIn && state.profile;
  const link = (id, label, cls) => el('a', { href: '#/' + id, class: cls + (r.name === id ? ' is-on' : ''), 'aria-current': r.name === id ? 'page' : null }, label);
  document.getElementById('brandMark').replaceChildren(emblem('moon', '#d8cbff', '#fff'));
  document.getElementById('topNav').replaceChildren(...NAV.filter(n => signed || n[0] === '' || n[0] === 'leaderboard').map(n => link(n[0], n[1], 'top__link')));
  document.getElementById('tabs').replaceChildren(...NAV.filter(n => signed || n[0] === '' || n[0] === 'leaderboard').map(n => link(n[0], n[1], 'tabs__item')));
  const end = document.getElementById('topEnd');
  if (signed) {
    end.replaceChildren(el('a', { class: 'balance', href: '#/packs', 'aria-label': 'Stardust balance' }, coin(state.profile.balance)),
      el('a', { class: 'me', href: '#/u/' + state.profile.username, 'aria-label': 'Your profile' }, avatar(state.profile, 34)),
      el('a', { class: 'iconlink', href: '#/settings' }, 'Settings'));
  } else {
    end.replaceChildren(el('a', { class: 'btn btn--small btn--ghost', href: '#/auth?mode=login' }, 'Log in'), el('a', { class: 'btn btn--small', href: '#/auth?mode=signup' }, 'Play free'));
  }
}

async function route() {
  const my = ++seq;
  const r = parse();
  const def = ROUTES[r.name];
  if (current && current.cleanup) { try { current.cleanup(); } catch (e) { /* ignore */ } }
  current = null;
  if (!def) { view.replaceChildren(el('div', { class: 'page' }, el('h1', { class: 'page-title' }, 'Page not found'), el('a', { class: 'btn', href: '#/' }, 'Go home'))); chrome(); return; }
  if (def.need && !auth.signedIn) { location.hash = '#/auth?mode=login'; return; }
  if (def.need && !state.profile) { try { setMe(await rpc('get_me')); } catch (e) { /* handled below */ } if (!state.profile) { location.hash = '#/welcome'; return; } }
  view.replaceChildren(el('p', { class: 'loading', role: 'status' }, 'Loading'));
  try {
    const mod = await def.load();
    const fn = mod[def.fn || 'render'];
    const node = await fn({ arg: r.arg, params: r.params });
    if (my !== seq) return; // user already moved on
    current = fn;
    view.replaceChildren(node);
  } catch (e) {
    if (my !== seq) return;
    view.replaceChildren(el('div', { class: 'page' }, el('h1', { class: 'page-title' }, 'Something went wrong'), el('p', { class: 'muted' }, friendly(e)), el('button', { class: 'btn', type: 'button', onclick: () => route() }, 'Try again')));
  }
  chrome();
  window.scrollTo(0, 0);
  if (my === seq) view.focus({ preventScroll: true });
}

function setup() {
  view.replaceChildren(el('div', { class: 'page page--narrow' }, el('h1', { class: 'page-title' }, 'Almost ready'),
    el('p', { class: 'muted' }, 'This site is not connected to a database yet. Open config.js and fill in SUPABASE_URL and SUPABASE_ANON_KEY, then reload. The README has the steps.')));
}

async function boot() {
  chrome();
  if (!configured) { setup(); return; }
  view.replaceChildren(el('p', { class: 'loading', role: 'status' }, 'Loading'));
  try {
    setCatalog(await rpc('get_catalog'));
    if (auth.signedIn) { try { setMe(await rpc('get_me')); } catch (e) { if (!auth.signedIn) clearMe(); } }
  } catch (e) {
    view.replaceChildren(el('div', { class: 'page page--narrow' }, el('h1', { class: 'page-title' }, 'Cannot load the game'), el('p', { class: 'muted' }, friendly(e)), el('button', { class: 'btn', type: 'button', onclick: () => location.reload() }, 'Reload')));
    return;
  }
  subscribe(chrome);
  auth.onChange(s => { if (!s) { clearMe(); if (['packs', 'collection', 'settings'].includes(parse().name)) location.hash = '#/'; } });
  window.addEventListener('hashchange', route);
  await route();
}
boot();
