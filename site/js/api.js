// Thin client for Supabase's REST API (auth, database functions, storage).
// No libraries, no build step. The game logic lives on the server; this file only sends requests.

const CFG = window.NEXORA || {};
const BASE = String(CFG.SUPABASE_URL || '').replace(/\/+$/, '');
const KEY = CFG.SUPABASE_ANON_KEY || '';
const SESSION_KEY = 'nexora.session';

export const configured = Boolean(BASE && KEY);

export class ApiError extends Error {
  constructor(message, code, status) { super(message); this.code = code; this.status = status; }
}

let session = null;
try { session = JSON.parse(localStorage.getItem(SESSION_KEY) || 'null'); } catch (e) { session = null; }
const listeners = new Set();

function setSession(s) {
  session = s;
  try { s ? localStorage.setItem(SESSION_KEY, JSON.stringify(s)) : localStorage.removeItem(SESSION_KEY); } catch (e) { /* storage blocked */ }
  listeners.forEach(fn => fn(session));
}

function normalizeSession(d) {
  if (!d || !d.access_token) return null;
  const exp = d.expires_at ? d.expires_at * 1000 : Date.now() + (d.expires_in || 3600) * 1000;
  return { access_token: d.access_token, refresh_token: d.refresh_token, expires_at: exp, user: d.user ? { id: d.user.id, email: d.user.email } : (session && session.user) };
}

async function request(path, { method = 'POST', body, token, headers = {}, raw } = {}) {
  const h = { apikey: KEY, ...headers };
  if (token) h.Authorization = 'Bearer ' + token;
  if (body !== undefined && !raw) h['Content-Type'] = 'application/json';
  let res;
  try {
    res = await fetch(BASE + path, { method, headers: h, body: raw ? body : (body !== undefined ? JSON.stringify(body) : undefined) });
  } catch (e) {
    throw new ApiError('network', 'network', 0);
  }
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (e) { data = null; }
  if (!res.ok) {
    const code = (data && (data.error_code || data.code)) || String(res.status);
    const msg = (data && (data.message || data.msg || data.error_description || data.error)) || 'request_failed';
    throw new ApiError(msg, code, res.status);
  }
  return data;
}

export const auth = {
  get session() { return session; },
  get user() { return session ? session.user : null; },
  get signedIn() { return Boolean(session && session.access_token); },
  onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },

  async signUp(email, password) {
    const d = await request('/auth/v1/signup', { body: { email, password } });
    const s = normalizeSession(d);
    if (!s) throw new ApiError('confirm_email', 'confirm_email', 200);
    setSession(s);
    return s;
  },
  async signIn(email, password) {
    const d = await request('/auth/v1/token?grant_type=password', { body: { email, password } });
    const s = normalizeSession(d);
    if (!s) throw new ApiError('invalid_credentials', 'invalid_credentials', 400);
    setSession(s);
    return s;
  },
  async signOut() {
    const tok = session && session.access_token;
    setSession(null);
    if (tok) { try { await request('/auth/v1/logout', { token: tok }); } catch (e) { /* already signed out locally */ } }
  },
  // Returns a valid access token, refreshing it shortly before it expires.
  async token() {
    if (!session) return null;
    if (session.expires_at - Date.now() > 60000) return session.access_token;
    try {
      const d = await request('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: session.refresh_token } });
      const s = normalizeSession(d);
      if (!s) throw new Error('no session');
      setSession(s);
      return s.access_token;
    } catch (e) {
      if (e instanceof ApiError && e.status === 0) return session.access_token; // offline: try with the old token
      setSession(null);
      return null;
    }
  }
};

// Call a database function. Args use the parameter names from the SQL (p_...).
export async function rpc(fn, args = {}) {
  const token = await auth.token();
  return request('/rest/v1/rpc/' + fn, { body: args, token });
}

export async function uploadProfileImage(blob, kind) {
  const user = auth.user;
  const token = await auth.token();
  if (!user || !token) throw new ApiError('not_signed_in', 'not_signed_in', 401);
  const ext = blob.type === 'image/webp' ? 'webp' : (blob.type === 'image/png' ? 'png' : 'jpg');
  const path = `${user.id}/${kind}-${Date.now()}.${ext}`;
  await request('/storage/v1/object/profiles/' + path, { body: blob, raw: true, token, headers: { 'Content-Type': blob.type, 'x-upsert': 'false' } });
  return `${BASE}/storage/v1/object/public/profiles/${path}`;
}
