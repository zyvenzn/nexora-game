// Shared app state. Pages read from here and call setMe() when the server sends back a fresh "me".
export const state = {
  cat: null,        // catalog from the server: rarities, cards, packs, recipes, config
  defs: {},         // card id -> card definition
  rar: {},          // rarity id -> rarity
  packTypes: {},    // pack id -> pack type
  me: null,         // full get_me() result
  profile: null,    // me.profile
  packs: {}         // pack id -> quantity owned
};
const subs = new Set();

export function subscribe(fn) { subs.add(fn); return () => subs.delete(fn); }
function emit() { subs.forEach(fn => fn(state)); }

export function setCatalog(cat) {
  state.cat = cat;
  state.defs = Object.fromEntries(cat.cards.map(c => [c.id, c]));
  state.rar = Object.fromEntries(cat.rarities.map(r => [r.id, r]));
  state.packTypes = Object.fromEntries(cat.packs.map(p => [p.id, p]));
  emit();
}

export function setMe(me) {
  state.me = me || null;
  state.profile = me && me.profile ? me.profile : null;
  state.packs = me && me.packs ? me.packs : {};
  emit();
}

export function clearMe() { setMe(null); }
