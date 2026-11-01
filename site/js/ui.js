// Small UI toolkit: element builder, pixel art pieces, cards, packs, toasts, error text.
import { state } from './state.js';

/* ---------------- element builder (text is always inserted as text, never as HTML) ---------------- */
export function el(tag, attrs, ...kids) {
  const n = document.createElement(tag);
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === 'class') n.className = v;
      else if (k === 'style') n.style.cssText = v;
      else if (k === 'html') n.innerHTML = v; // only used with fixed strings written in this code base
      else if (k.startsWith('on') && typeof v === 'function') n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v === true ? '' : v);
    }
  }
  add(n, kids);
  return n;
}
function add(n, kids) {
  for (const k of kids.flat(Infinity)) {
    if (k == null || k === false) continue;
    n.append(k instanceof Node ? k : document.createTextNode(String(k)));
  }
}
export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
export const clear = n => { n.replaceChildren(); return n; };

/* ---------------- numbers and time ---------------- */
export const fmt = n => Number(n || 0).toLocaleString('en-US');
export const coin = n => '✦ ' + fmt(n);

export function ago(iso) {
  const s = Math.max(1, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
  if (s < 60) return 'just now';
  const m = Math.round(s / 60); if (m < 60) return m + ' min ago';
  const h = Math.round(m / 60); if (h < 24) return h + ' h ago';
  return Math.round(h / 24) + ' d ago';
}
export function until(iso) {
  const ms = new Date(iso).getTime() - Date.now();
  if (ms <= 0) return 'now';
  const s = Math.ceil(ms / 1000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m`;
  return `${m}m ${String(sec).padStart(2, '0')}s`;
}

/* ---------------- pixel emblems (drawn from text grids) ---------------- */
const GRIDS = {
  moon: ['...####....', '..###......', '.###.......', '.###.......', '###........', '###........', '###........', '.###.......', '.###.......', '..###......', '...####....'],
  flame: ['....#......', '....##.....', '...###.....', '...####..#.', '..#####.##.', '..########.', '.#########.', '.####+####.', '.###+++###.', '.###+++###.', '..###+###..', '...#####...'],
  drop: ['.....#.....', '.....#.....', '....###....', '....###....', '...#####...', '..#######..', '.####+####.', '.###++####.', '.###+#####.', '.#########.', '..#######..', '...#####...'],
  spark: ['.....#.....', '.....#.....', '....###....', '....###....', '...#####...', '#####+#####', '...#####...', '....###....', '....###....', '.....#.....', '.....#.....'],
  gem: ['...###...', '..#####..', '.#######.', '#########', '.#######.', '..#####..', '...###...', '....#....']
};
export function emblem(name, main = '#fff', light = '#fff') {
  const g = GRIDS[name] || GRIDS.moon, w = g[0].length, h = g.length;
  let r = '';
  g.forEach((row, y) => { for (let x = 0; x < w; x++) {
    const c = row[x];
    if (c === '#') r += `<rect x="${x}" y="${y}" width="1.02" height="1.02" fill="${main}"/>`;
    else if (c === '+') r += `<rect x="${x}" y="${y}" width="1.02" height="1.02" fill="${light}"/>`;
  } });
  const s = el('span', { class: 'emblem', html: `<svg viewBox="0 0 ${w} ${h}" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">${r}</svg>` });
  return s;
}

/* ---------------- packs ---------------- */
const PACK_LOOK = {
  starter:   { a: '#8df0cf', b: '#2f9a86', glyph: '#f2fffb', emblem: 'moon' },
  celestial: { a: '#c4a8ff', b: '#ff9fd2', glyph: '#fff6ff', emblem: 'moon' },
  ember:     { a: '#ffb15c', b: '#dc4430', glyph: '#fff1d6', emblem: 'flame' },
  tide:      { a: '#6fe6ea', b: '#2f6fda', glyph: '#eaffff', emblem: 'drop' },
  void:      { a: '#4a3585', b: '#120a2a', glyph: '#e9b8ff', emblem: 'spark' },
  forged:    { a: '#ffd36b', b: '#c4562a', glyph: '#fff7df', emblem: 'flame' }
};
export function packLook(p) {
  return PACK_LOOK[p.id] || PACK_LOOK[p.element] || { a: '#b79bff', b: '#5a3fbf', glyph: '#fff', emblem: 'moon' };
}
const TEETH = 14, TOOTH = 2.4;
const CRIMP = (() => {
  const pts = [];
  for (let i = 0; i <= TEETH; i++) pts.push((i * 100 / TEETH).toFixed(2) + '% ' + (i % 2 ? TOOTH : 0) + '%');
  for (let i = TEETH; i >= 0; i--) pts.push((i * 100 / TEETH).toFixed(2) + '% ' + (i % 2 ? 100 : 100 - TOOTH) + '%');
  return 'polygon(' + pts.join(',') + ')';
})();

// The look of a booster pack. Pass an element wrapper if you want it clickable.
export function packArt(p) {
  const look = packLook(p);
  const shell = el('span', { class: 'pack__shell' });
  shell.style.clipPath = CRIMP; shell.style.webkitClipPath = CRIMP;
  const body = el('span', { class: 'pack__body' },
    el('span', { class: 'pack__emblem' }, emblem(look.emblem, look.glyph, '#fff')),
    el('span', { class: 'pack__name' }, p.name.replace(/ Pack$/, '')),
    el('span', { class: 'pack__sub' }, 'Nexora booster'));
  const art = el('span', { class: 'pack', 'data-pack': p.id }, shell, body);
  art.style.setProperty('--a', look.a); art.style.setProperty('--b', look.b); art.style.setProperty('--glyph', look.glyph);
  return art;
}

/* ---------------- cards ---------------- */
export const NAME_COLOR = { common: '#3b4250', uncommon: '#1d3b24', rare: '#14305a', epic: '#2f1457', celestial: '#4a3300' };
export const rarityColor = id => (state.rar[id] && state.rar[id].color) || '#aab1bf';
export const rarityName = id => (state.rar[id] && state.rar[id].name) || id;

// A card picture. `def` needs id/name/rarity/image. opts: mini (no name on card), locked, serial, count.
export function cardEl(def, opts = {}) {
  const c = el('div', { class: 'tcard' + (opts.mini ? ' tcard--mini' : '') + (opts.locked ? ' is-locked' : '') });
  c.style.setProperty('--name-color', NAME_COLOR[def.rarity] || '#3b4250');
  const img = el('img', { src: def.image, alt: opts.locked ? 'Card not found yet' : `${def.name}, ${rarityName(def.rarity)}`, draggable: 'false', decoding: 'async' });
  c.append(img, el('span', { class: 'tcard__watermark', 'aria-hidden': 'true' }, 'NEXORA'));
  if (!opts.locked) {
    const element = def.element || 'celestial';
    const value = def.value ?? def.base_price ?? null;
    c.append(el('span', { class: 'tcard__element tcard__element--' + element }, element.toUpperCase()));
    c.append(el('span', { class: 'tcard__rarity' }, rarityName(def.rarity)));
    if (value !== null) c.append(el('span', { class: 'tcard__price' }, '✦ ' + fmt(value)));
  }
  if (!opts.locked && !opts.mini) c.append(el('span', { class: 'tcard__name' }, def.name));
  if (opts.count > 1) c.append(el('span', { class: 'tcard__count' }, 'x' + opts.count));
  if (opts.badge) c.append(el('span', { class: 'tcard__badge' }, opts.badge));
  return c;
}
// Same card but made from a server card object (has all fields inline)
export const defOf = obj => state.defs[obj.def_id || obj.id] || obj;

export function chip(rarity) {
  const c = el('span', { class: 'chip' }, rarityName(rarity));
  c.style.setProperty('--c', rarityColor(rarity));
  return c;
}

/* ---------------- avatar ---------------- */
export function avatar(user, size = 40) {
  const a = el('span', { class: 'avatar', style: `width:${size}px;height:${size}px;font-size:${Math.round(size * 0.42)}px` });
  if (user && user.avatar_url) a.append(el('img', { src: user.avatar_url, alt: '', loading: 'lazy' }));
  else a.append(((user && (user.display_name || user.username)) || '?').trim().charAt(0).toUpperCase());
  return a;
}

/* ---------------- toasts ---------------- */
export function toast(message, kind = 'info') {
  const root = document.getElementById('toasts');
  if (!root) return;
  const t = el('div', { class: 'toast toast--' + kind, role: kind === 'error' ? 'alert' : 'status' }, message);
  root.append(t);
  setTimeout(() => t.classList.add('is-out'), 3600);
  setTimeout(() => t.remove(), 4100);
}

/* ---------------- error text ---------------- */
const MESSAGES = {
  network: 'Cannot reach the server. Check your connection and try again.',
  not_signed_in: 'Log in first.', no_profile: 'Pick a username to finish your account.', banned: 'This account is suspended.',
  insufficient_funds: 'Not enough Stardust.', no_pack: 'You have no pack of that kind to open.', unknown_pack: 'That pack does not exist.',
  bad_quantity: 'Choose between 1 and 20 packs.', daily_not_ready: 'Your daily bonus is not ready yet.',
  username_taken: 'That username is taken.', username_reserved: 'That username is reserved.',
  bad_username: 'Usernames use 3 to 20 letters, numbers or underscores.', username_cooldown: 'You can change your username once a week.',
  bad_display_name: 'Display name must be 1 to 30 characters.', bad_bio: 'Bio can be up to 160 characters.',
  bad_image_url: 'That image could not be used. Try uploading again.', profile_exists: 'You already have a profile.',
  no_such_player: 'No player with that name.', not_your_card: 'That card is not yours.', card_busy: 'That card is already in a sale, auction or trade.',
  bad_price: 'Enter a price of at least 1.', too_many_listings: 'You have too many active listings.', listing_gone: 'That listing is gone.',
  own_listing: 'You cannot buy your own listing.', price_changed: 'The price changed. Refresh and check again.', not_yours: 'That is not yours.',
  bad_duration: 'Choose an allowed duration.', too_many_auctions: 'You have too many active auctions.', auction_gone: 'That auction is gone.',
  auction_ended: 'That auction has ended.', own_auction: 'You cannot bid on your own auction.', bid_too_low: 'Your bid is too low.', has_bids: 'This auction already has bids.',
  self_trade: 'You cannot trade with yourself.', empty_trade: 'Add something to the offer.', too_many_items: 'Up to 12 cards per side.',
  duplicate_items: 'A card was added twice.', their_card_unavailable: 'One of their cards is no longer available.', trade_gone: 'That trade is gone.',
  trade_closed: 'That trade is already closed.', trade_expired: 'That trade expired.', items_unavailable: 'One of the cards in this trade is no longer available.',
  too_many_trades: 'You have too many open trades.', bad_amount: 'That amount is not allowed.', message_too_long: 'Message is too long.',
  bad_craft_items: 'Pick exactly the required number of cards of the right rarity.', unknown_recipe: 'That recipe does not exist.',
  bad_reason: 'Please describe the problem in a few words.', report_limit: 'Too many reports today.', player_unavailable: 'That player cannot trade right now.',
  not_admin: 'Admins only.', confirm_email: 'Check your email to confirm your account, then log in.',
  invalid_credentials: 'Wrong email or password.', user_already_exists: 'That email already has an account. Try logging in.',
  email_exists: 'That email already has an account. Try logging in.', weak_password: 'Password is too weak. Use at least 8 characters.',
  over_email_send_rate_limit: 'Too many attempts. Wait a minute and try again.', validation_failed: 'Check the email address and try again.',
  signup_disabled: 'Sign ups are closed right now.'
};
export function friendly(err) {
  if (!err) return 'Something went wrong.';
  const code = err.code, msg = err.message || '';
  if (MESSAGES[msg]) return MESSAGES[msg];
  if (MESSAGES[code]) return MESSAGES[code];
  if (/invalid login credentials/i.test(msg)) return MESSAGES.invalid_credentials;
  if (/already registered|already been registered/i.test(msg)) return MESSAGES.user_already_exists;
  if (/password/i.test(msg) && /(short|least|weak)/i.test(msg)) return MESSAGES.weak_password;
  if (/jwt|token/i.test(msg) && /expired|invalid/i.test(msg)) return 'Your session expired. Log in again.';
  return 'Something went wrong. Try again.';
}

/* ---------------- images ---------------- */
// Crop to the target aspect ratio and shrink, so uploads stay small.
export async function prepareImage(file, w, h, quality = 0.86) {
  if (!/^image\/(png|jpe?g|webp)$/.test(file.type)) throw new Error('bad_image_type');
  if (file.size > 12 * 1024 * 1024) throw new Error('bad_image_size');
  const bmp = await createImageBitmap(file);
  const scale = Math.max(w / bmp.width, h / bmp.height);
  const sw = w / scale, sh = h / scale, sx = (bmp.width - sw) / 2, sy = (bmp.height - sh) / 2;
  const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
  cv.getContext('2d').drawImage(bmp, sx, sy, sw, sh, 0, 0, w, h);
  let blob = await new Promise(r => cv.toBlob(r, 'image/webp', quality));
  if (!blob || blob.type !== 'image/webp') blob = await new Promise(r => cv.toBlob(r, 'image/jpeg', quality));
  return blob;
}

/* ---------------- misc ---------------- */
export function setTitle(t) { document.title = t ? `${t} | Nexora` : 'Nexora'; }
export function reducedMotion() { return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches; }
