-- =====================================================================
-- Nexora game backend, part 1: tables, settings, seed data
-- Play money only. There is no cash-out anywhere in this schema.
-- =====================================================================

-- ---------- settings (admin editable) ----------
create table public.settings (
  key   text primary key,
  value jsonb not null
);
insert into public.settings (key, value) values
  ('starting_balance',     '500'),
  ('daily_bonus',          '100'),
  ('daily_hours',          '20'),
  ('market_fee_pct',       '5'),
  ('trade_expiry_hours',   '48'),
  ('max_listings',         '40'),
  ('max_auctions',         '10'),
  ('max_open_trades',      '10'),
  ('username_change_days', '7'),
  ('auction_min_hours',    '1'),
  ('auction_max_hours',    '72'),
  ('snipe_window_min',     '2');

-- ---------- catalog ----------
create table public.rarities (
  id         text primary key,
  name       text not null,
  rank       int  not null unique,
  score      int  not null,        -- leaderboard points per card
  base_price int  not null,        -- reference price in Stardust
  color      text not null
);
insert into public.rarities (id, name, rank, score, base_price, color) values
  ('common',    'Common',    0,   1,   10, '#aab1bf'),
  ('uncommon',  'Uncommon',  1,   4,   40, '#5fbf6b'),
  ('rare',      'Rare',      2,  15,  150, '#4f9cf0'),
  ('epic',      'Epic',      3,  60,  600, '#a86bf0'),
  ('celestial', 'Celestial', 4, 300, 3000, '#ffd36b');

create table public.card_defs (
  id         text primary key,
  name       text not null,
  rarity     text not null references public.rarities(id),
  element    text not null check (element in ('celestial','ember','tide','void')),
  image      text not null,
  blurb      text not null default '',
  base_price int,                  -- null = use the rarity's base price
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
insert into public.card_defs (id, name, rarity, element, image, blurb) values
  ('common-01',   'Sleepy Luna',   'common',   'celestial', 'assets/cards/common-01.png',   'Naps on a crescent moon. Does nothing else.'),
  ('common-02',   'Starcatcher',   'common',   'celestial', 'assets/cards/common-02.png',   'Caught one star. Will not share.'),
  ('common-03',   'Cinder Puff',   'common',   'ember',     'assets/cards/common-03.png',   'Breathes sparks. Has set nothing on fire. Yet.'),
  ('common-04',   'Magma Pup',     'common',   'ember',     'assets/cards/common-04.png',   'Stands on a volcano like it paid for it.'),
  ('common-05',   'Wave Hopper',   'common',   'tide',      'assets/cards/common-05.png',   'Surprised by the ocean. Every single time.'),
  ('common-06',   'Bubble Drift',  'common',   'tide',      'assets/cards/common-06.png',   'Went for a swim. Forgot to come back.'),
  ('common-07',   'Shade Peek',    'common',   'void',      'assets/cards/common-07.png',   'Hiding. You can see it. It does not know.'),
  ('common-08',   'Void Drifter',  'common',   'void',      'assets/cards/common-08.png',   'Floats through space. No destination.'),
  ('uncommon-01', 'Emerald Gloom', 'uncommon', 'void',      'assets/cards/uncommon-01.png', 'Wears a green gem. Will not say where it got it.');

create table public.card_serials (
  def_id      text primary key references public.card_defs(id),
  last_serial int not null default 0
);

create table public.pack_types (
  id              text primary key,
  name            text not null,
  description     text not null default '',
  element         text check (element in ('celestial','ember','tide','void')),
  price           int  not null default 0 check (price >= 0),
  cards_count     int  not null check (cards_count between 1 and 12),
  odds            jsonb not null,           -- weight per rarity id
  guarantee_rarity text references public.rarities(id), -- last slot is at least this rare
  element_bias    int  not null default 3,  -- own element weight vs 1
  purchasable     boolean not null default true,
  active          boolean not null default true,
  sort            int  not null default 0
);
insert into public.pack_types (id, name, description, element, price, cards_count, odds, guarantee_rarity, element_bias, purchasable, sort) values
  ('starter',   'Starter Pack',   'One free pack for every new player.',            null,        0,   4, '{"common":85,"uncommon":15}', null,       1, false, 0),
  ('celestial', 'Celestial Pack', 'Moonlit dragons. Leans Celestial.',              'celestial', 100, 4, '{"common":70,"uncommon":24,"rare":5,"epic":0.9,"celestial":0.1}', null, 3, true, 1),
  ('ember',     'Ember Pack',     'Warm scales and loose sparks. Leans Ember.',     'ember',     100, 4, '{"common":70,"uncommon":24,"rare":5,"epic":0.9,"celestial":0.1}', null, 3, true, 2),
  ('tide',      'Tide Pack',      'Deep water and bubbles. Leans Tide.',            'tide',      100, 4, '{"common":70,"uncommon":24,"rare":5,"epic":0.9,"celestial":0.1}', null, 3, true, 3),
  ('void',      'Void Pack',      'Dark corners and cold stars. Leans Void.',       'void',      100, 4, '{"common":70,"uncommon":24,"rare":5,"epic":0.9,"celestial":0.1}', null, 3, true, 4),
  ('forged',    'Forged Pack',    'Made by crafting. Five cards, last one Uncommon or better.', null, 0, 5, '{"common":50,"uncommon":38,"rare":9,"epic":2.5,"celestial":0.5}', 'uncommon', 1, false, 5);

create table public.craft_recipes (
  id            text primary key,
  name          text not null,
  input_rarity  text not null references public.rarities(id),
  input_qty     int  not null check (input_qty > 0),
  output_pack   text not null references public.pack_types(id),
  active        boolean not null default true
);
insert into public.craft_recipes (id, name, input_rarity, input_qty, output_pack) values
  ('forge-uncommon', '40 Uncommon into a Forged Pack', 'uncommon', 40, 'forged'),
  ('forge-common',   '100 Common into a Celestial Pack', 'common', 100, 'celestial');

-- ---------- players ----------
create table public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  username         text not null,
  display_name     text not null,
  bio              text not null default '',
  avatar_url       text,
  banner_url       text,
  balance          bigint not null default 0 check (balance >= 0),
  role             text not null default 'player' check (role in ('player','admin')),
  banned           boolean not null default false,
  ban_reason       text,
  last_daily       timestamptz,
  username_changed_at timestamptz,
  created_at       timestamptz not null default now()
);
create unique index profiles_username_key on public.profiles (lower(username));

create table public.cards_owned (
  id           uuid primary key default gen_random_uuid(),
  owner        uuid not null references public.profiles(id),
  def_id       text not null references public.card_defs(id),
  serial       int  not null,
  status       text not null default 'owned' check (status in ('owned','listed','auction','trade','burned')),
  acquired_via text not null default 'pack',
  acquired_at  timestamptz not null default now()
);
create index cards_owned_owner_idx on public.cards_owned (owner) where status <> 'burned';
create index cards_owned_def_idx   on public.cards_owned (def_id);

create table public.pack_inventory (
  user_id   uuid not null references public.profiles(id),
  pack_type text not null references public.pack_types(id),
  qty       int  not null default 0 check (qty >= 0),
  primary key (user_id, pack_type)
);

create table public.pack_openings (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references public.profiles(id),
  pack_type text not null,
  cards     jsonb not null,
  at        timestamptz not null default now()
);

create table public.ledger (
  id            bigserial primary key,
  user_id       uuid not null references public.profiles(id),
  delta         bigint not null,
  balance_after bigint not null,
  reason        text not null,
  ref           text,
  at            timestamptz not null default now()
);
create index ledger_user_idx on public.ledger (user_id, id desc);

-- ---------- market ----------
create table public.listings (
  id          uuid primary key default gen_random_uuid(),
  seller      uuid not null references public.profiles(id),
  instance_id uuid not null references public.cards_owned(id),
  price       bigint not null check (price > 0),
  status      text not null default 'active' check (status in ('active','sold','cancelled')),
  buyer       uuid references public.profiles(id),
  created_at  timestamptz not null default now(),
  sold_at     timestamptz
);
create unique index listings_one_active_idx on public.listings (instance_id) where status = 'active';
create index listings_active_idx on public.listings (created_at desc) where status = 'active';

create table public.sales (
  id     bigserial primary key,
  def_id text not null references public.card_defs(id),
  price  bigint not null,
  kind   text not null,
  at     timestamptz not null default now()
);
create index sales_def_idx on public.sales (def_id, id desc);

create table public.auctions (
  id             uuid primary key default gen_random_uuid(),
  seller         uuid not null references public.profiles(id),
  instance_id    uuid not null references public.cards_owned(id),
  start_price    bigint not null check (start_price > 0),
  current_bid    bigint not null default 0,
  current_bidder uuid references public.profiles(id),
  bid_count      int not null default 0,
  ends_at        timestamptz not null,
  status         text not null default 'active' check (status in ('active','sold','expired','cancelled')),
  created_at     timestamptz not null default now(),
  settled_at     timestamptz
);
create unique index auctions_one_active_idx on public.auctions (instance_id) where status = 'active';
create index auctions_active_idx on public.auctions (ends_at) where status = 'active';

create table public.bids (
  id         bigserial primary key,
  auction_id uuid not null references public.auctions(id),
  bidder     uuid not null references public.profiles(id),
  amount     bigint not null,
  at         timestamptz not null default now()
);
create index bids_auction_idx on public.bids (auction_id, id desc);

-- ---------- trades ----------
create table public.trades (
  id          uuid primary key default gen_random_uuid(),
  from_user   uuid not null references public.profiles(id),
  to_user     uuid not null references public.profiles(id),
  from_coins  bigint not null default 0 check (from_coins >= 0),
  to_coins    bigint not null default 0 check (to_coins >= 0),
  message     text not null default '',
  status      text not null default 'pending' check (status in ('pending','accepted','declined','cancelled','expired')),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  resolved_at timestamptz,
  check (from_user <> to_user)
);
create index trades_to_idx   on public.trades (to_user, status);
create index trades_from_idx on public.trades (from_user, status);

create table public.trade_items (
  trade_id    uuid not null references public.trades(id) on delete cascade,
  instance_id uuid not null references public.cards_owned(id),
  side        text not null check (side in ('from','to')),
  primary key (trade_id, instance_id)
);

-- ---------- community / admin ----------
create table public.reports (
  id         uuid primary key default gen_random_uuid(),
  reporter   uuid not null references public.profiles(id),
  target     uuid not null references public.profiles(id),
  trade_id   uuid references public.trades(id),
  reason     text not null,
  status     text not null default 'open' check (status in ('open','resolved','dismissed')),
  note       text,
  handled_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  handled_at timestamptz
);

create table public.feed (
  id      bigserial primary key,
  kind    text not null,
  user_id uuid references public.profiles(id),
  payload jsonb not null,
  at      timestamptz not null default now()
);

create table public.audit_log (
  id       bigserial primary key,
  admin_id uuid not null references public.profiles(id),
  action   text not null,
  target   text,
  details  jsonb,
  at       timestamptz not null default now()
);
-- =====================================================================
-- Part 2: helpers, accounts, packs, collection, crafting
-- Every function below runs with the owner's rights; tables are not
-- readable or writable by players directly (see 05_security.sql).
-- Error messages are short codes the website turns into sentences.
-- =====================================================================

-- ---------- helpers (not callable from the website) ----------
create or replace function public._cfg(k text) returns bigint
language sql stable set search_path = public, pg_temp as $$
  select (value #>> '{}')::bigint from public.settings where key = k
$$;

create or replace function public._uid() returns uuid
language plpgsql stable set search_path = public, pg_temp as $$
declare u uuid;
begin
  u := auth.uid();
  if u is null then raise exception 'not_signed_in'; end if;
  return u;
end $$;

create or replace function public._player() returns public.profiles
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = public._uid();
  if not found then raise exception 'no_profile'; end if;
  if p.banned then raise exception 'banned'; end if;
  return p;
end $$;

create or replace function public._admin() returns public.profiles
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p public.profiles;
begin
  p := public._player();
  if p.role <> 'admin' then raise exception 'not_admin'; end if;
  return p;
end $$;

create or replace function public._lock_profiles(a uuid, b uuid) returns void
language sql security definer set search_path = public, pg_temp as $$
  select 1 from public.profiles where id in (a, b) order by id for update
$$;

create or replace function public._coins(p_uid uuid, p_delta bigint, p_reason text, p_ref text default null)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare nb bigint;
begin
  update public.profiles set balance = balance + p_delta
   where id = p_uid and balance + p_delta >= 0
   returning balance into nb;
  if not found then
    if exists (select 1 from public.profiles where id = p_uid) then
      raise exception 'insufficient_funds';
    end if;
    raise exception 'no_profile';
  end if;
  insert into public.ledger (user_id, delta, balance_after, reason, ref)
  values (p_uid, p_delta, nb, p_reason, p_ref);
  return nb;
end $$;

create or replace function public._mint(p_owner uuid, p_def text, p_via text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare sn int; iid uuid;
begin
  insert into public.card_serials (def_id, last_serial) values (p_def, 1)
  on conflict (def_id) do update set last_serial = public.card_serials.last_serial + 1
  returning last_serial into sn;
  insert into public.cards_owned (owner, def_id, serial, acquired_via)
  values (p_owner, p_def, sn, p_via) returning id into iid;
  return iid;
end $$;

create or replace function public._add_pack(p_uid uuid, p_pack text, p_qty int) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.pack_inventory (user_id, pack_type, qty) values (p_uid, p_pack, p_qty)
  on conflict (user_id, pack_type) do update set qty = public.pack_inventory.qty + excluded.qty
$$;

-- Reference value of a card: average of its last 5 sales, else its base price.
create or replace function public._value(p_def text) returns bigint
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    (select round(avg(price))::bigint from (select price from public.sales where def_id = p_def order by id desc limit 5) s),
    (select coalesce(d.base_price, r.base_price)::bigint from public.card_defs d join public.rarities r on r.id = d.rarity where d.id = p_def)
  )
$$;

create or replace function public._card_obj(p_instance uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'id', co.id, 'def_id', d.id, 'name', d.name, 'rarity', d.rarity, 'rank', r.rank,
    'element', d.element, 'image', d.image, 'blurb', d.blurb, 'serial', co.serial,
    'status', co.status, 'value', public._value(d.id))
  from public.cards_owned co
  join public.card_defs d on d.id = co.def_id
  join public.rarities r on r.id = d.rarity
  where co.id = p_instance
$$;

create or replace function public._pick_weighted(ids text[], w numeric[]) returns text
language plpgsql as $$
declare tot numeric := 0; r numeric; acc numeric := 0; i int;
begin
  for i in 1..coalesce(array_length(w, 1), 0) loop tot := tot + w[i]; end loop;
  if tot <= 0 then
    return ids[1 + floor(random() * array_length(ids, 1))::int];
  end if;
  r := random() * tot;
  for i in 1..array_length(ids, 1) loop
    acc := acc + w[i];
    if r < acc then return ids[i]; end if;
  end loop;
  return ids[array_length(ids, 1)];
end $$;

create or replace function public._user_json(p_uid uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('id', id, 'username', username, 'display_name', display_name, 'avatar_url', avatar_url)
  from public.profiles where id = p_uid
$$;

create or replace function public._audit(p_action text, p_target text, p_details jsonb default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.audit_log (admin_id, action, target, details) values (public._uid(), p_action, p_target, p_details);
end $$;

-- ---------- account ----------
create or replace function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select lower(trim(p_username)) ~ '^[a-z0-9_]{3,20}$'
     and lower(trim(p_username)) <> all (array['admin','administrator','nexora','support','system','moderator','mod','staff','official','root'])
     and not exists (select 1 from public.profiles where lower(username) = lower(trim(p_username)))
$$;

create or replace function public.create_profile(p_username text, p_display text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := public._uid(); u text := lower(trim(coalesce(p_username, ''))); dn text := nullif(trim(coalesce(p_display, '')), '');
begin
  if exists (select 1 from public.profiles where id = uid) then raise exception 'profile_exists'; end if;
  if u !~ '^[a-z0-9_]{3,20}$' then raise exception 'bad_username'; end if;
  if u = any (array['admin','administrator','nexora','support','system','moderator','mod','staff','official','root']) then
    raise exception 'username_reserved';
  end if;
  if exists (select 1 from public.profiles where lower(username) = u) then raise exception 'username_taken'; end if;
  dn := coalesce(left(dn, 30), u);
  insert into public.profiles (id, username, display_name) values (uid, u, dn);
  perform public._coins(uid, public._cfg('starting_balance'), 'welcome');
  perform public._add_pack(uid, 'starter', 1);
  return public.get_me();
exception when unique_violation then
  raise exception 'username_taken';
end $$;

create or replace function public.get_me() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = public._uid();
  if not found then return jsonb_build_object('signed_in', true, 'profile', null); end if;
  return jsonb_build_object(
    'signed_in', true,
    'profile', jsonb_build_object(
      'id', p.id, 'username', p.username, 'display_name', p.display_name, 'bio', p.bio,
      'avatar_url', p.avatar_url, 'banner_url', p.banner_url, 'balance', p.balance,
      'role', p.role, 'banned', p.banned, 'ban_reason', p.ban_reason, 'created_at', p.created_at,
      'next_daily_at', case when p.last_daily is null then null
                            else p.last_daily + make_interval(hours => public._cfg('daily_hours')::int) end),
    'packs', (select coalesce(jsonb_object_agg(pack_type, qty), '{}'::jsonb) from public.pack_inventory where user_id = p.id and qty > 0),
    'incoming_trades', (select count(*) from public.trades where to_user = p.id and status = 'pending' and expires_at > now()),
    'config', jsonb_build_object('fee_pct', public._cfg('market_fee_pct'), 'daily_bonus', public._cfg('daily_bonus'))
  );
end $$;

create or replace function public.update_profile(p_display text default null, p_bio text default null,
                                                 p_avatar text default null, p_banner text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); dn text; marker text;
begin
  marker := '/storage/v1/object/public/profiles/' || me.id::text || '/';
  if p_display is not null then
    dn := trim(p_display);
    if char_length(dn) < 1 or char_length(dn) > 30 or dn ~ '[\x00-\x1f]' then raise exception 'bad_display_name'; end if;
  end if;
  if p_bio is not null and (char_length(p_bio) > 160 or p_bio ~ '[\x00-\x08\x0b-\x1f]') then raise exception 'bad_bio'; end if;
  if p_avatar is not null and p_avatar <> '' and (p_avatar !~ '^https://' or position(marker in p_avatar) = 0) then raise exception 'bad_image_url'; end if;
  if p_banner is not null and p_banner <> '' and (p_banner !~ '^https://' or position(marker in p_banner) = 0) then raise exception 'bad_image_url'; end if;
  update public.profiles set
    display_name = coalesce(dn, display_name),
    bio          = coalesce(p_bio, bio),
    avatar_url   = case when p_avatar is null then avatar_url when p_avatar = '' then null else p_avatar end,
    banner_url   = case when p_banner is null then banner_url when p_banner = '' then null else p_banner end
  where id = me.id;
  return public.get_me();
end $$;

create or replace function public.change_username(p_new text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); u text := lower(trim(coalesce(p_new, '')));
begin
  if me.username_changed_at is not null
     and me.username_changed_at + make_interval(days => public._cfg('username_change_days')::int) > now() then
    raise exception 'username_cooldown';
  end if;
  if u !~ '^[a-z0-9_]{3,20}$' then raise exception 'bad_username'; end if;
  if u = any (array['admin','administrator','nexora','support','system','moderator','mod','staff','official','root']) then
    raise exception 'username_reserved';
  end if;
  if exists (select 1 from public.profiles where lower(username) = u and id <> me.id) then raise exception 'username_taken'; end if;
  update public.profiles set username = u, username_changed_at = now() where id = me.id;
  return public.get_me();
exception when unique_violation then
  raise exception 'username_taken';
end $$;

create or replace function public.claim_daily() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); bonus bigint := public._cfg('daily_bonus');
begin
  select * into me from public.profiles where id = me.id for update;
  if me.last_daily is not null and now() < me.last_daily + make_interval(hours => public._cfg('daily_hours')::int) then
    raise exception 'daily_not_ready';
  end if;
  update public.profiles set last_daily = now() where id = me.id;
  perform public._coins(me.id, bonus, 'daily');
  return public.get_me();
end $$;

-- ---------- catalog and feed (public) ----------
create or replace function public.get_catalog() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'rarities', (select coalesce(jsonb_agg(to_jsonb(r) order by r.rank), '[]'::jsonb) from public.rarities r),
    'cards', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', d.id, 'name', d.name, 'rarity', d.rarity, 'element', d.element, 'image', d.image,
        'blurb', d.blurb, 'value', public._value(d.id),
        'floor', (select min(l.price) from public.listings l join public.cards_owned c on c.id = l.instance_id where l.status = 'active' and c.def_id = d.id),
        'last_sale', (select s.price from public.sales s where s.def_id = d.id order by s.id desc limit 1),
        'minted', coalesce((select last_serial from public.card_serials cs where cs.def_id = d.id), 0),
        'holders', (select count(distinct owner) from public.cards_owned c where c.def_id = d.id and c.status <> 'burned')
      ) order by r.rank, d.id), '[]'::jsonb)
      from public.card_defs d join public.rarities r on r.id = d.rarity where d.active),
    'packs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'description', description, 'element', element, 'price', price,
        'cards_count', cards_count, 'odds', odds, 'guarantee_rarity', guarantee_rarity, 'purchasable', purchasable
      ) order by sort), '[]'::jsonb) from public.pack_types where active),
    'recipes', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.craft_recipes c where active),
    'config', jsonb_build_object('fee_pct', public._cfg('market_fee_pct'), 'daily_bonus', public._cfg('daily_bonus'),
                                 'daily_hours', public._cfg('daily_hours'), 'trade_expiry_hours', public._cfg('trade_expiry_hours'))
  )
$$;

create or replace function public.feed_recent(p_limit int default 12) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', f.kind, 'at', f.at, 'payload', f.payload,
           'user', public._user_json(f.user_id)) order by f.id desc), '[]'::jsonb)
  from (select * from public.feed order by id desc limit least(greatest(p_limit, 1), 50)) f
$$;

-- ---------- packs ----------
create or replace function public.buy_pack(p_pack text, p_qty int default 1) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); pt public.pack_types;
begin
  if p_qty is null or p_qty < 1 or p_qty > 20 then raise exception 'bad_quantity'; end if;
  select * into pt from public.pack_types where id = p_pack and active and purchasable;
  if not found then raise exception 'unknown_pack'; end if;
  perform public._coins(me.id, -(pt.price::bigint * p_qty), 'buy_pack', pt.id);
  perform public._add_pack(me.id, pt.id, p_qty);
  return public.get_me();
end $$;

create or replace function public.open_pack(p_pack text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  me public.profiles := public._player();
  pt public.pack_types;
  g_rank int; is_last boolean;
  rids text[]; rw numeric[]; cids text[]; cw numeric[];
  chosen_r text; chosen_d text; iid uuid;
  owned_defs text[]; out jsonb := '[]'::jsonb; obj jsonb; is_new boolean; rk int;
  i int;
begin
  select * into pt from public.pack_types where id = p_pack and active;
  if not found then raise exception 'unknown_pack'; end if;
  update public.pack_inventory set qty = qty - 1
   where user_id = me.id and pack_type = pt.id and qty > 0;
  if not found then raise exception 'no_pack'; end if;

  if pt.guarantee_rarity is not null then
    select rank into g_rank from public.rarities where id = pt.guarantee_rarity;
  end if;
  select coalesce(array_agg(distinct def_id), '{}') into owned_defs
    from public.cards_owned where owner = me.id and status <> 'burned';

  for i in 1..pt.cards_count loop
    is_last := (i = pt.cards_count);
    select array_agg(r.id order by r.rank), array_agg(coalesce((pt.odds ->> r.id)::numeric, 0) order by r.rank)
      into rids, rw
      from public.rarities r
     where exists (select 1 from public.card_defs d where d.rarity = r.id and d.active)
       and (not is_last or g_rank is null or r.rank >= g_rank);
    if rids is null then
      select array_agg(r.id order by r.rank), array_agg(coalesce((pt.odds ->> r.id)::numeric, 0) order by r.rank)
        into rids, rw
        from public.rarities r
       where exists (select 1 from public.card_defs d where d.rarity = r.id and d.active);
    end if;
    if rids is null then raise exception 'no_cards'; end if;
    chosen_r := public._pick_weighted(rids, rw);
    select array_agg(d.id order by d.id),
           array_agg((case when d.element = pt.element then pt.element_bias else 1 end)::numeric order by d.id)
      into cids, cw
      from public.card_defs d where d.rarity = chosen_r and d.active;
    chosen_d := public._pick_weighted(cids, cw);
    iid := public._mint(me.id, chosen_d, 'pack');
    is_new := not (chosen_d = any (owned_defs));
    owned_defs := owned_defs || chosen_d;
    obj := public._card_obj(iid) || jsonb_build_object('is_new', is_new);
    out := out || jsonb_build_array(obj);
    rk := (obj ->> 'rank')::int;
    if rk >= 1 then
      insert into public.feed (kind, user_id, payload)
      values ('pull', me.id, jsonb_build_object('name', obj ->> 'name', 'rarity', obj ->> 'rarity', 'def_id', chosen_d, 'serial', (obj ->> 'serial')::int, 'pack', pt.id));
    end if;
  end loop;

  insert into public.pack_openings (user_id, pack_type, cards) values (me.id, pt.id, out);
  return jsonb_build_object('pack', pt.id, 'cards', out, 'me', public.get_me());
end $$;

-- ---------- collection ----------
create or replace function public.my_collection() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player();
begin
  return jsonb_build_object(
    'cards', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'def_id', def_id, 'serial', serial, 'status', status,
                'via', acquired_via, 'at', acquired_at) order by acquired_at desc, serial), '[]'::jsonb)
              from public.cards_owned where owner = me.id and status <> 'burned'),
    'packs', (select coalesce(jsonb_object_agg(pack_type, qty), '{}'::jsonb) from public.pack_inventory where user_id = me.id and qty > 0));
end $$;

create or replace function public.craft_pack(p_recipe text, p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); rc public.craft_recipes; n int; good int;
begin
  select * into rc from public.craft_recipes where id = p_recipe and active;
  if not found then raise exception 'unknown_recipe'; end if;
  n := coalesce(array_length(p_ids, 1), 0);
  if n <> rc.input_qty or (select count(distinct x) from unnest(p_ids) x) <> n then raise exception 'bad_craft_items'; end if;
  perform 1 from public.cards_owned where id = any (p_ids) order by id for update;
  select count(*) into good from public.cards_owned co join public.card_defs d on d.id = co.def_id
   where co.id = any (p_ids) and co.owner = me.id and co.status = 'owned' and d.rarity = rc.input_rarity;
  if good <> n then raise exception 'bad_craft_items'; end if;
  update public.cards_owned set status = 'burned' where id = any (p_ids);
  perform public._add_pack(me.id, rc.output_pack, 1);
  return jsonb_build_object('pack', rc.output_pack, 'me', public.get_me());
end $$;
-- =====================================================================
-- Part 3: marketplace, auctions, trades, reports
-- Safety rules built in:
--  * a card in a listing, auction or trade is locked (status), so it
--    can never be in two deals at once
--  * the buyer pays exactly the price they saw (expected price check)
--  * trade offers cannot be edited after creation, only cancelled
--  * the sender's items and coins are held (escrow) until the offer ends
--  * the swap itself is one all-or-nothing transaction
-- =====================================================================

-- ---------- marketplace ----------
create or replace function public.list_card(p_instance uuid, p_price bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); co public.cards_owned; lid uuid;
begin
  select * into co from public.cards_owned where id = p_instance and owner = me.id for update;
  if not found then raise exception 'not_your_card'; end if;
  if co.status <> 'owned' then raise exception 'card_busy'; end if;
  if p_price is null or p_price < 1 or p_price > 10000000 then raise exception 'bad_price'; end if;
  if (select count(*) from public.listings where seller = me.id and status = 'active') >= public._cfg('max_listings') then
    raise exception 'too_many_listings';
  end if;
  insert into public.listings (seller, instance_id, price) values (me.id, co.id, p_price) returning id into lid;
  update public.cards_owned set status = 'listed' where id = co.id;
  return jsonb_build_object('listing_id', lid);
end $$;

create or replace function public.cancel_listing(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); l public.listings;
begin
  select * into l from public.listings where id = p_id for update;
  if not found or l.status <> 'active' then raise exception 'listing_gone'; end if;
  if l.seller <> me.id then raise exception 'not_yours'; end if;
  update public.listings set status = 'cancelled' where id = l.id;
  update public.cards_owned set status = 'owned' where id = l.instance_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.buy_listing(p_id uuid, p_expected bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); l public.listings; fee bigint; pct bigint := public._cfg('market_fee_pct'); did text;
begin
  select * into l from public.listings where id = p_id for update;
  if not found or l.status <> 'active' then raise exception 'listing_gone'; end if;
  if l.seller = me.id then raise exception 'own_listing'; end if;
  if l.price <> p_expected then raise exception 'price_changed'; end if;
  perform public._lock_profiles(me.id, l.seller);
  fee := case when pct <= 0 then 0 else greatest(1, floor(l.price * pct / 100.0))::bigint end;
  perform public._coins(me.id, -l.price, 'market_buy', l.id::text);
  perform public._coins(l.seller, l.price - fee, 'market_sale', l.id::text);
  update public.cards_owned set owner = me.id, status = 'owned', acquired_via = 'market' where id = l.instance_id
    returning def_id into did;
  update public.listings set status = 'sold', buyer = me.id, sold_at = now() where id = l.id;
  insert into public.sales (def_id, price, kind) values (did, l.price, 'market');
  insert into public.feed (kind, user_id, payload)
    values ('sale', me.id, jsonb_build_object('name', (public._card_obj(l.instance_id)) ->> 'name', 'price', l.price, 'def_id', did));
  return jsonb_build_object('card', public._card_obj(l.instance_id), 'me', public.get_me());
end $$;

create or replace function public.market_browse(p_rarity text default null, p_element text default null, p_search text default null,
                                                p_sort text default 'new', p_limit int default 30, p_offset int default 0) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  with rows as (
    select l.id, l.price, l.created_at, l.seller,
           row_number() over (order by
             case when p_sort = 'price_asc'  then l.price end asc,
             case when p_sort = 'price_desc' then l.price end desc,
             case when p_sort = 'rarity'     then r.rank end desc,
             l.created_at desc) as rn,
           l.instance_id
      from public.listings l
      join public.cards_owned co on co.id = l.instance_id
      join public.card_defs d on d.id = co.def_id
      join public.rarities r on r.id = d.rarity
     where l.status = 'active'
       and (p_rarity is null or d.rarity = p_rarity)
       and (p_element is null or d.element = p_element)
       and (p_search is null or p_search = '' or d.name ilike '%' || replace(replace(p_search, '%', ''), '_', '') || '%')
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'price', price, 'created_at', created_at,
           'seller', public._user_json(seller), 'card', public._card_obj(instance_id)) order by rn), '[]'::jsonb)
  from rows where rn > greatest(p_offset, 0) and rn <= greatest(p_offset, 0) + least(greatest(p_limit, 1), 60)
$$;

create or replace function public.my_listings() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'price', price, 'created_at', created_at,
            'card', public._card_obj(instance_id)) order by created_at desc)
          from public.listings where seller = me.id and status = 'active'), '[]'::jsonb);
end $$;

-- ---------- auctions ----------
create or replace function public.settle_due_auctions() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.auctions; fee bigint; pct bigint := public._cfg('market_fee_pct'); n int := 0; did text;
begin
  for a in select * from public.auctions where status = 'active' and ends_at <= now() order by ends_at for update skip locked loop
    if a.current_bidder is null then
      update public.cards_owned set status = 'owned' where id = a.instance_id;
      update public.auctions set status = 'expired', settled_at = now() where id = a.id;
    else
      fee := case when pct <= 0 then 0 else greatest(1, floor(a.current_bid * pct / 100.0))::bigint end;
      perform public._coins(a.seller, a.current_bid - fee, 'auction_sale', a.id::text);
      update public.cards_owned set owner = a.current_bidder, status = 'owned', acquired_via = 'auction'
       where id = a.instance_id returning def_id into did;
      insert into public.sales (def_id, price, kind) values (did, a.current_bid, 'auction');
      update public.auctions set status = 'sold', settled_at = now() where id = a.id;
      insert into public.feed (kind, user_id, payload)
        values ('auction', a.current_bidder, jsonb_build_object('name', (public._card_obj(a.instance_id)) ->> 'name', 'price', a.current_bid, 'def_id', did));
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.create_auction(p_instance uuid, p_start bigint, p_hours int) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); co public.cards_owned; aid uuid;
begin
  select * into co from public.cards_owned where id = p_instance and owner = me.id for update;
  if not found then raise exception 'not_your_card'; end if;
  if co.status <> 'owned' then raise exception 'card_busy'; end if;
  if p_start is null or p_start < 1 or p_start > 10000000 then raise exception 'bad_price'; end if;
  if p_hours is null or p_hours < public._cfg('auction_min_hours') or p_hours > public._cfg('auction_max_hours') then
    raise exception 'bad_duration';
  end if;
  if (select count(*) from public.auctions where seller = me.id and status = 'active') >= public._cfg('max_auctions') then
    raise exception 'too_many_auctions';
  end if;
  insert into public.auctions (seller, instance_id, start_price, ends_at)
  values (me.id, co.id, p_start, now() + make_interval(hours => p_hours)) returning id into aid;
  update public.cards_owned set status = 'auction' where id = co.id;
  return jsonb_build_object('auction_id', aid);
end $$;

create or replace function public.place_bid(p_id uuid, p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); a public.auctions; min_bid bigint; win interval;
begin
  select * into a from public.auctions where id = p_id for update;
  if not found or a.status <> 'active' then raise exception 'auction_gone'; end if;
  if a.ends_at <= now() then raise exception 'auction_ended'; end if;
  if a.seller = me.id then raise exception 'own_auction'; end if;
  min_bid := case when a.current_bidder is null then a.start_price
                  else a.current_bid + greatest(1, ceil(a.current_bid * 0.05))::bigint end;
  if p_amount is null or p_amount < min_bid then raise exception 'bid_too_low'; end if;
  if a.current_bidder is not null then
    perform public._lock_profiles(me.id, a.current_bidder);
    perform public._coins(a.current_bidder, a.current_bid, 'bid_refund', a.id::text);
  end if;
  perform public._coins(me.id, -p_amount, 'bid_hold', a.id::text);
  win := make_interval(mins => public._cfg('snipe_window_min')::int);
  update public.auctions set current_bid = p_amount, current_bidder = me.id, bid_count = bid_count + 1,
         ends_at = case when ends_at - now() < win then now() + win else ends_at end
   where id = a.id;
  insert into public.bids (auction_id, bidder, amount) values (a.id, me.id, p_amount);
  return jsonb_build_object('me', public.get_me(), 'ends_at', (select ends_at from public.auctions where id = a.id));
end $$;

create or replace function public.cancel_auction(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); a public.auctions;
begin
  select * into a from public.auctions where id = p_id for update;
  if not found or a.status <> 'active' then raise exception 'auction_gone'; end if;
  if a.seller <> me.id then raise exception 'not_yours'; end if;
  if a.bid_count > 0 then raise exception 'has_bids'; end if;
  update public.auctions set status = 'cancelled', settled_at = now() where id = a.id;
  update public.cards_owned set status = 'owned' where id = a.instance_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public._auction_obj(p_id uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('id', a.id, 'status', a.status, 'start_price', a.start_price, 'current_bid', a.current_bid,
    'bid_count', a.bid_count, 'ends_at', a.ends_at, 'created_at', a.created_at,
    'min_next_bid', case when a.current_bidder is null then a.start_price
                         else a.current_bid + greatest(1, ceil(a.current_bid * 0.05))::bigint end,
    'seller', public._user_json(a.seller), 'leader', public._user_json(a.current_bidder),
    'card', public._card_obj(a.instance_id))
  from public.auctions a where a.id = p_id
$$;

create or replace function public.auction_browse(p_rarity text default null, p_element text default null,
                                                 p_sort text default 'ending', p_limit int default 30, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public.settle_due_auctions();
  return (
    with rows as (
      select a.id, row_number() over (order by
               case when p_sort = 'rarity' then r.rank end desc,
               case when p_sort = 'price'  then a.current_bid end desc,
               a.ends_at asc) as rn
        from public.auctions a
        join public.cards_owned co on co.id = a.instance_id
        join public.card_defs d on d.id = co.def_id
        join public.rarities r on r.id = d.rarity
       where a.status = 'active'
         and (p_rarity is null or d.rarity = p_rarity)
         and (p_element is null or d.element = p_element)
    )
    select coalesce(jsonb_agg(public._auction_obj(id) order by rn), '[]'::jsonb)
      from rows where rn > greatest(p_offset, 0) and rn <= greatest(p_offset, 0) + least(greatest(p_limit, 1), 60)
  );
end $$;

create or replace function public.my_auctions() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player();
begin
  perform public.settle_due_auctions();
  return jsonb_build_object(
    'selling', (select coalesce(jsonb_agg(public._auction_obj(id) order by ends_at), '[]'::jsonb)
                from public.auctions where seller = me.id and status = 'active'),
    'bidding', (select coalesce(jsonb_agg(public._auction_obj(id) order by ends_at), '[]'::jsonb)
                from public.auctions where status = 'active' and id in (select auction_id from public.bids where bidder = me.id)));
end $$;

-- ---------- trades ----------
-- Return the held items and coins to the sender and close the offer.
create or replace function public._trade_release(p_id uuid, p_status text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare t public.trades;
begin
  select * into t from public.trades where id = p_id and status = 'pending' for update;
  if not found then return; end if;
  update public.cards_owned set status = 'owned'
   where status = 'trade' and id in (select instance_id from public.trade_items where trade_id = t.id and side = 'from');
  if t.from_coins > 0 then perform public._coins(t.from_user, t.from_coins, 'trade_refund', t.id::text); end if;
  update public.trades set status = p_status, resolved_at = now() where id = t.id;
end $$;

create or replace function public._expire_trades() returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare t record;
begin
  for t in select id from public.trades where status = 'pending' and expires_at <= now() order by id for update skip locked loop
    perform public._trade_release(t.id, 'expired');
  end loop;
end $$;

create or replace function public._trade_obj(p_id uuid, p_viewer uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare t public.trades; vg bigint := 0; vw bigint := 0; give jsonb; want jsonb; other uuid; unfair boolean := false; stats jsonb;
begin
  select * into t from public.trades where id = p_id;
  select coalesce(jsonb_agg(public._card_obj(instance_id)), '[]'::jsonb) into give from public.trade_items where trade_id = t.id and side = 'from';
  select coalesce(jsonb_agg(public._card_obj(instance_id)), '[]'::jsonb) into want from public.trade_items where trade_id = t.id and side = 'to';
  select coalesce(sum((x ->> 'value')::bigint), 0) into vg from jsonb_array_elements(give) x;
  select coalesce(sum((x ->> 'value')::bigint), 0) into vw from jsonb_array_elements(want) x;
  vg := vg + t.from_coins; vw := vw + t.to_coins;
  -- "unfair" for whoever would receive much less value than they give
  if t.status = 'pending' then
    if p_viewer = t.to_user and vw > 0 and vg * 2 < vw then unfair := true; end if;
    if p_viewer = t.from_user and vg > 0 and vw * 2 < vg then unfair := true; end if;
  end if;
  other := case when p_viewer = t.from_user then t.to_user else t.from_user end;
  select jsonb_build_object(
      'age_days', floor(extract(epoch from (now() - p.created_at)) / 86400),
      'trades_done', (select count(*) from public.trades x where x.status = 'accepted' and (x.from_user = p.id or x.to_user = p.id)),
      'reports_open', (select count(*) from public.reports r where r.target = p.id and r.status <> 'dismissed')
    ) into stats from public.profiles p where p.id = other;
  return jsonb_build_object('id', t.id, 'status', t.status, 'message', t.message, 'created_at', t.created_at,
    'expires_at', t.expires_at, 'resolved_at', t.resolved_at,
    'from', public._user_json(t.from_user), 'to', public._user_json(t.to_user),
    'give', give, 'give_coins', t.from_coins, 'want', want, 'want_coins', t.to_coins,
    'give_value', vg, 'want_value', vw, 'unfair', unfair, 'partner', stats,
    'direction', case when p_viewer = t.from_user then 'out' else 'in' end);
end $$;

create or replace function public.create_trade(p_to text, p_give uuid[], p_want uuid[], p_give_coins bigint default 0,
                                               p_want_coins bigint default 0, p_message text default '') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); target public.profiles; tid uuid;
        ng int := coalesce(array_length(p_give, 1), 0); nw int := coalesce(array_length(p_want, 1), 0);
begin
  perform public._expire_trades();
  select * into target from public.profiles where lower(username) = lower(trim(coalesce(p_to, '')));
  if not found then raise exception 'no_such_player'; end if;
  if target.id = me.id then raise exception 'self_trade'; end if;
  if target.banned then raise exception 'player_unavailable'; end if;
  if coalesce(p_give_coins, 0) < 0 or coalesce(p_want_coins, 0) < 0 then raise exception 'bad_amount'; end if;
  if ng + nw = 0 and coalesce(p_give_coins, 0) + coalesce(p_want_coins, 0) = 0 then raise exception 'empty_trade'; end if;
  if ng > 12 or nw > 12 then raise exception 'too_many_items'; end if;
  if (select count(distinct x) from unnest(coalesce(p_give, '{}')) x) <> ng or (select count(distinct x) from unnest(coalesce(p_want, '{}')) x) <> nw then
    raise exception 'duplicate_items';
  end if;
  if length(coalesce(p_message, '')) > 140 then raise exception 'message_too_long'; end if;
  if (select count(*) from public.trades where from_user = me.id and status = 'pending') >= public._cfg('max_open_trades') then
    raise exception 'too_many_trades';
  end if;

  if ng > 0 then
    perform 1 from public.cards_owned where id = any (p_give) order by id for update;
    if (select count(*) from public.cards_owned where id = any (p_give) and owner = me.id and status = 'owned') <> ng then
      raise exception 'card_busy';
    end if;
  end if;
  if nw > 0 and (select count(*) from public.cards_owned where id = any (p_want) and owner = target.id and status = 'owned') <> nw then
    raise exception 'their_card_unavailable';
  end if;

  insert into public.trades (from_user, to_user, from_coins, to_coins, message, expires_at)
  values (me.id, target.id, coalesce(p_give_coins, 0), coalesce(p_want_coins, 0), coalesce(p_message, ''),
          now() + make_interval(hours => public._cfg('trade_expiry_hours')::int))
  returning id into tid;
  if ng > 0 then
    insert into public.trade_items (trade_id, instance_id, side) select tid, x, 'from' from unnest(p_give) x;
    update public.cards_owned set status = 'trade' where id = any (p_give);
  end if;
  if nw > 0 then
    insert into public.trade_items (trade_id, instance_id, side) select tid, x, 'to' from unnest(p_want) x;
  end if;
  if coalesce(p_give_coins, 0) > 0 then perform public._coins(me.id, -p_give_coins, 'trade_escrow', tid::text); end if;
  return jsonb_build_object('trade_id', tid);
end $$;

create or replace function public.get_trade(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); t public.trades;
begin
  perform public._expire_trades();
  select * into t from public.trades where id = p_id;
  if not found or (t.from_user <> me.id and t.to_user <> me.id) then raise exception 'trade_gone'; end if;
  return public._trade_obj(t.id, me.id);
end $$;

create or replace function public.my_trades() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player();
begin
  perform public._expire_trades();
  return jsonb_build_object(
    'pending', (select coalesce(jsonb_agg(public._trade_obj(id, me.id) order by created_at desc), '[]'::jsonb)
                from public.trades where status = 'pending' and (from_user = me.id or to_user = me.id)),
    'history', (select coalesce(jsonb_agg(public._trade_obj(id, me.id) order by resolved_at desc), '[]'::jsonb)
                from (select * from public.trades where status <> 'pending' and (from_user = me.id or to_user = me.id)
                      order by resolved_at desc nulls last limit 20) h));
end $$;

create or replace function public.accept_trade(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); t public.trades; nw int;
begin
  select * into t from public.trades where id = p_id for update;
  if not found or t.to_user <> me.id then raise exception 'trade_gone'; end if;
  if t.status <> 'pending' then raise exception 'trade_closed'; end if;
  if t.expires_at <= now() then
    perform public._trade_release(t.id, 'expired');
    raise exception 'trade_expired';
  end if;
  perform public._lock_profiles(t.from_user, t.to_user);
  select count(*) into nw from public.trade_items where trade_id = t.id and side = 'to';
  if nw > 0 then
    perform 1 from public.cards_owned where id in (select instance_id from public.trade_items where trade_id = t.id and side = 'to') order by id for update;
    if (select count(*) from public.cards_owned co where co.owner = me.id and co.status = 'owned'
          and co.id in (select instance_id from public.trade_items where trade_id = t.id and side = 'to')) <> nw then
      raise exception 'items_unavailable';
    end if;
  end if;
  if t.to_coins > 0 then
    perform public._coins(me.id, -t.to_coins, 'trade_pay', t.id::text);
    perform public._coins(t.from_user, t.to_coins, 'trade_receive', t.id::text);
  end if;
  if t.from_coins > 0 then perform public._coins(me.id, t.from_coins, 'trade_receive', t.id::text); end if;
  update public.cards_owned set owner = me.id, status = 'owned', acquired_via = 'trade'
   where id in (select instance_id from public.trade_items where trade_id = t.id and side = 'from');
  update public.cards_owned set owner = t.from_user, status = 'owned', acquired_via = 'trade'
   where id in (select instance_id from public.trade_items where trade_id = t.id and side = 'to');
  update public.trades set status = 'accepted', resolved_at = now() where id = t.id;
  return jsonb_build_object('me', public.get_me());
end $$;

create or replace function public.decline_trade(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); t public.trades;
begin
  select * into t from public.trades where id = p_id;
  if not found or t.to_user <> me.id then raise exception 'trade_gone'; end if;
  if t.status <> 'pending' then raise exception 'trade_closed'; end if;
  perform public._trade_release(t.id, 'declined');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.cancel_trade(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); t public.trades;
begin
  select * into t from public.trades where id = p_id;
  if not found or t.from_user <> me.id then raise exception 'trade_gone'; end if;
  if t.status <> 'pending' then raise exception 'trade_closed'; end if;
  perform public._trade_release(t.id, 'cancelled');
  return jsonb_build_object('me', public.get_me());
end $$;

create or replace function public.report_user(p_username text, p_reason text, p_trade uuid default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); target public.profiles;
begin
  select * into target from public.profiles where lower(username) = lower(trim(coalesce(p_username, '')));
  if not found then raise exception 'no_such_player'; end if;
  if target.id = me.id then raise exception 'self_report'; end if;
  if char_length(trim(coalesce(p_reason, ''))) < 5 or char_length(p_reason) > 300 then raise exception 'bad_reason'; end if;
  if (select count(*) from public.reports where reporter = me.id and created_at > now() - interval '1 day') >= 5 then
    raise exception 'report_limit';
  end if;
  insert into public.reports (reporter, target, trade_id, reason) values (me.id, target.id, p_trade, trim(p_reason));
  return jsonb_build_object('ok', true);
end $$;
-- =====================================================================
-- Part 4: leaderboard, public profiles, admin panel
-- =====================================================================

-- ---------- scores ----------
create or replace function public._scores() returns table (
  user_id uuid, score bigint, total int, uniq int, best_rank int)
language sql stable security definer set search_path = public, pg_temp as $$
  select co.owner, sum(r.score)::bigint, count(*)::int, count(distinct co.def_id)::int, max(r.rank)::int
    from public.cards_owned co
    join public.card_defs d on d.id = co.def_id
    join public.rarities r on r.id = d.rarity
   where co.status <> 'burned'
   group by co.owner
$$;

create or replace function public.get_leaderboard(p_limit int default 50, p_mode text default 'score') returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  with s as (
    select * from public._scores()
  ), ranked as (
    select s.*, p.username, p.display_name, p.avatar_url,
           row_number() over (order by
             case when p_mode = 'rarest' then s.best_rank end desc nulls last,
             case when p_mode = 'collectors' then s.uniq end desc nulls last,
             s.score desc, s.total desc, p.created_at) as pos
      from s join public.profiles p on p.id = s.user_id
     where not p.banned
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'pos', pos, 'username', username, 'display_name', display_name, 'avatar_url', avatar_url,
      'score', score, 'total', total, 'unique', uniq,
      'rarest', (select jsonb_build_object('name', d.name, 'rarity', d.rarity, 'serial', co.serial, 'def_id', d.id)
                   from public.cards_owned co join public.card_defs d on d.id = co.def_id join public.rarities r on r.id = d.rarity
                  where co.owner = ranked.user_id and co.status <> 'burned'
                  order by r.rank desc, co.serial limit 1)
    ) order by pos), '[]'::jsonb)
  from ranked where pos <= least(greatest(p_limit, 1), 100)
$$;

create or replace function public.get_public_profile(p_username text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p public.profiles; sc record; pos int; active_defs int;
begin
  select * into p from public.profiles where lower(username) = lower(trim(coalesce(p_username, '')));
  if not found then raise exception 'no_such_player'; end if;
  select * into sc from public._scores() where user_id = p.id;
  select count(*) + 1 into pos from public._scores() x join public.profiles q on q.id = x.user_id
   where not q.banned and x.score > coalesce(sc.score, 0);
  select count(*) into active_defs from public.card_defs where active;
  return jsonb_build_object(
    'username', p.username, 'display_name', p.display_name, 'bio', p.bio,
    'avatar_url', p.avatar_url, 'banner_url', p.banner_url, 'banned', p.banned, 'created_at', p.created_at,
    'score', coalesce(sc.score, 0), 'total', coalesce(sc.total, 0), 'unique', coalesce(sc.uniq, 0),
    'completion', case when active_defs = 0 then 0 else round(100.0 * coalesce(sc.uniq, 0) / active_defs) end,
    'rank', case when p.banned then null else pos end,
    'trades_done', (select count(*) from public.trades x where x.status = 'accepted' and (x.from_user = p.id or x.to_user = p.id)),
    'showcase', (select coalesce(jsonb_agg(public._card_obj(id) order by rk desc, serial), '[]'::jsonb)
                   from (select co.id, r.rank as rk, co.serial from public.cards_owned co
                           join public.card_defs d on d.id = co.def_id join public.rarities r on r.id = d.rarity
                          where co.owner = p.id and co.status <> 'burned'
                          order by r.rank desc, co.serial limit 12) q),
    'for_sale', (select count(*) from public.listings where seller = p.id and status = 'active'));
end $$;

-- Someone else's tradable cards (for building a trade offer).
create or replace function public.player_cards(p_username text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare me public.profiles := public._player(); p public.profiles;
begin
  select * into p from public.profiles where lower(username) = lower(trim(coalesce(p_username, '')));
  if not found then raise exception 'no_such_player'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', co.id, 'def_id', co.def_id, 'serial', co.serial) order by r.rank desc, co.serial)
                     from public.cards_owned co join public.card_defs d on d.id = co.def_id join public.rarities r on r.id = d.rarity
                    where co.owner = p.id and co.status = 'owned'), '[]'::jsonb);
end $$;

-- ---------- admin ----------
create or replace function public.admin_overview() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return jsonb_build_object(
    'players', (select count(*) from public.profiles),
    'banned', (select count(*) from public.profiles where banned),
    'cards', (select count(*) from public.cards_owned where status <> 'burned'),
    'stardust', (select coalesce(sum(balance), 0) from public.profiles),
    'listings', (select count(*) from public.listings where status = 'active'),
    'auctions', (select count(*) from public.auctions where status = 'active'),
    'trades_open', (select count(*) from public.trades where status = 'pending'),
    'reports_open', (select count(*) from public.reports where status = 'open'),
    'packs_opened', (select count(*) from public.pack_openings),
    'sales_24h', (select count(*) from public.sales where at > now() - interval '1 day'));
end $$;

create or replace function public.admin_users(p_search text default '', p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'username', username, 'display_name', display_name,
            'balance', balance, 'role', role, 'banned', banned, 'ban_reason', ban_reason, 'created_at', created_at,
            'cards', (select count(*) from public.cards_owned co where co.owner = q.id and co.status <> 'burned')) order by created_at desc)
          from (select * from public.profiles
                 where coalesce(p_search, '') = '' or username ilike '%' || replace(replace(p_search, '%', ''), '_', '') || '%'
                 order by created_at desc limit least(greatest(p_limit, 1), 100)) q), '[]'::jsonb);
end $$;

create or replace function public.admin_grant_coins(p_username text, p_amount bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); t public.profiles; nb bigint;
begin
  select * into t from public.profiles where lower(username) = lower(trim(p_username));
  if not found then raise exception 'no_such_player'; end if;
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000 then raise exception 'bad_amount'; end if;
  nb := public._coins(t.id, p_amount, 'admin', left(coalesce(p_reason, ''), 100));
  perform public._audit('grant_coins', t.username, jsonb_build_object('amount', p_amount, 'reason', p_reason));
  return jsonb_build_object('balance', nb);
end $$;

create or replace function public.admin_give_pack(p_username text, p_pack text, p_qty int default 1) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); t public.profiles;
begin
  select * into t from public.profiles where lower(username) = lower(trim(p_username));
  if not found then raise exception 'no_such_player'; end if;
  if not exists (select 1 from public.pack_types where id = p_pack) then raise exception 'unknown_pack'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 100 then raise exception 'bad_quantity'; end if;
  perform public._add_pack(t.id, p_pack, p_qty);
  perform public._audit('give_pack', t.username, jsonb_build_object('pack', p_pack, 'qty', p_qty));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_give_card(p_username text, p_def text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); t public.profiles; iid uuid;
begin
  select * into t from public.profiles where lower(username) = lower(trim(p_username));
  if not found then raise exception 'no_such_player'; end if;
  if not exists (select 1 from public.card_defs where id = p_def) then raise exception 'unknown_card'; end if;
  iid := public._mint(t.id, p_def, 'admin');
  perform public._audit('give_card', t.username, jsonb_build_object('def', p_def, 'instance', iid));
  return jsonb_build_object('instance_id', iid);
end $$;

create or replace function public.admin_set_ban(p_username text, p_banned boolean, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); t public.profiles; l record; au record;
begin
  select * into t from public.profiles where lower(username) = lower(trim(p_username));
  if not found then raise exception 'no_such_player'; end if;
  if t.role = 'admin' then raise exception 'cannot_ban_admin'; end if;
  update public.profiles set banned = coalesce(p_banned, false), ban_reason = case when p_banned then left(p_reason, 200) else null end where id = t.id;
  if p_banned then
    -- free their cards from deals so nothing stays stuck
    for l in select id from public.listings where seller = t.id and status = 'active' loop
      update public.listings set status = 'cancelled' where id = l.id;
    end loop;
    update public.cards_owned set status = 'owned' where owner = t.id and status = 'listed';
    for au in select id from public.auctions where seller = t.id and status = 'active' and bid_count = 0 loop
      update public.auctions set status = 'cancelled', settled_at = now() where id = au.id;
    end loop;
    update public.cards_owned set status = 'owned' where owner = t.id and status = 'auction'
      and id not in (select instance_id from public.auctions where status = 'active');
    perform public._trade_release(x.id, 'cancelled') from public.trades x where x.from_user = t.id and x.status = 'pending';
  end if;
  perform public._audit(case when p_banned then 'ban' else 'unban' end, t.username, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_upsert_card(p_def jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); cid text := lower(trim(p_def ->> 'id'));
begin
  if cid is null or cid !~ '^[a-z0-9-]{3,40}$' then raise exception 'bad_card_id'; end if;
  insert into public.card_defs (id, name, rarity, element, image, blurb, base_price, active)
  values (cid, p_def ->> 'name', p_def ->> 'rarity', p_def ->> 'element', p_def ->> 'image',
          coalesce(p_def ->> 'blurb', ''), nullif(p_def ->> 'base_price', '')::int, coalesce((p_def ->> 'active')::boolean, true))
  on conflict (id) do update set name = excluded.name, rarity = excluded.rarity, element = excluded.element,
     image = excluded.image, blurb = excluded.blurb, base_price = excluded.base_price, active = excluded.active;
  perform public._audit('upsert_card', cid, p_def);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_upsert_pack(p_pack jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); pid text := lower(trim(p_pack ->> 'id'));
begin
  if pid is null or pid !~ '^[a-z0-9-]{3,30}$' then raise exception 'bad_pack_id'; end if;
  insert into public.pack_types (id, name, description, element, price, cards_count, odds, guarantee_rarity, element_bias, purchasable, active, sort)
  values (pid, p_pack ->> 'name', coalesce(p_pack ->> 'description', ''), nullif(p_pack ->> 'element', ''),
          coalesce((p_pack ->> 'price')::int, 100), coalesce((p_pack ->> 'cards_count')::int, 4), coalesce(p_pack -> 'odds', '{"common":100}'::jsonb),
          nullif(p_pack ->> 'guarantee_rarity', ''), coalesce((p_pack ->> 'element_bias')::int, 3),
          coalesce((p_pack ->> 'purchasable')::boolean, true), coalesce((p_pack ->> 'active')::boolean, true), coalesce((p_pack ->> 'sort')::int, 10))
  on conflict (id) do update set name = excluded.name, description = excluded.description, element = excluded.element,
     price = excluded.price, cards_count = excluded.cards_count, odds = excluded.odds, guarantee_rarity = excluded.guarantee_rarity,
     element_bias = excluded.element_bias, purchasable = excluded.purchasable, active = excluded.active, sort = excluded.sort;
  perform public._audit('upsert_pack', pid, p_pack);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_set_setting(p_key text, p_value bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  if not exists (select 1 from public.settings where key = p_key) then raise exception 'unknown_setting'; end if;
  if p_value is null or p_value < 0 or p_value > 1000000 then raise exception 'bad_amount'; end if;
  update public.settings set value = to_jsonb(p_value) where key = p_key;
  perform public._audit('set_setting', p_key, to_jsonb(p_value));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_settings() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.settings);
end $$;

create or replace function public.admin_cancel_listing(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); l public.listings;
begin
  select * into l from public.listings where id = p_id for update;
  if not found or l.status <> 'active' then raise exception 'listing_gone'; end if;
  update public.listings set status = 'cancelled' where id = l.id;
  update public.cards_owned set status = 'owned' where id = l.instance_id;
  perform public._audit('cancel_listing', p_id::text, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_cancel_auction(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin(); au public.auctions;
begin
  select * into au from public.auctions where id = p_id for update;
  if not found or au.status <> 'active' then raise exception 'auction_gone'; end if;
  if au.current_bidder is not null then
    perform public._coins(au.current_bidder, au.current_bid, 'bid_refund', au.id::text);
  end if;
  update public.auctions set status = 'cancelled', settled_at = now() where id = au.id;
  update public.cards_owned set status = 'owned' where id = au.instance_id;
  perform public._audit('cancel_auction', p_id::text, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_cancel_trade(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  if not exists (select 1 from public.trades where id = p_id and status = 'pending') then raise exception 'trade_closed'; end if;
  perform public._trade_release(p_id, 'cancelled');
  perform public._audit('cancel_trade', p_id::text, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_reports(p_status text default 'open') returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'reason', r.reason, 'status', r.status, 'note', r.note,
            'created_at', r.created_at, 'trade_id', r.trade_id,
            'reporter', public._user_json(r.reporter), 'target', public._user_json(r.target)) order by r.created_at desc)
          from public.reports r where r.status = p_status), '[]'::jsonb);
end $$;

create or replace function public.admin_resolve_report(p_id uuid, p_status text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  if p_status not in ('resolved', 'dismissed') then raise exception 'bad_status'; end if;
  update public.reports set status = p_status, note = left(coalesce(p_note, ''), 300), handled_by = a.id, handled_at = now()
   where id = p_id and status = 'open';
  if not found then raise exception 'report_gone'; end if;
  perform public._audit('resolve_report', p_id::text, jsonb_build_object('status', p_status));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_audit(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare a public.profiles := public._admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'action', l.action, 'target', l.target, 'details', l.details,
            'admin', public._user_json(l.admin_id)) order by l.id desc)
          from (select * from public.audit_log order by id desc limit least(greatest(p_limit, 1), 200)) l), '[]'::jsonb);
end $$;
-- =====================================================================
-- Part 5: lock everything down
-- Players can only call the functions listed here. They cannot read or
-- write any table directly, so the browser cannot invent cards or coins.
-- =====================================================================

-- 1. Tables: row level security on, no policies, no direct privileges.
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
    execute format('revoke all on table public.%I from anon, authenticated', t.tablename);
  end loop;
  for t in select sequencename from pg_sequences where schemaname = 'public' loop
    execute format('revoke all on sequence public.%I from anon, authenticated', t.sequencename);
  end loop;
end $$;

-- 2. Functions: nobody by default; helpers (names starting with "_") stay private.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if left(f.proname, 1) <> '_' then
      execute format('grant execute on function %s to authenticated', f.sig);
      if f.proname = any (array['username_available', 'get_catalog', 'feed_recent', 'market_browse',
                                'auction_browse', 'get_leaderboard', 'get_public_profile']) then
        execute format('grant execute on function %s to anon', f.sig);
      end if;
    end if;
  end loop;
end $$;
-- =====================================================================
-- Part 6: storage for profile pictures and banners (public bucket, own folder only)
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profiles', 'profiles', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 2097152,
  allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];

drop policy if exists "nexora profiles read" on storage.objects;
drop policy if exists "nexora profiles insert own" on storage.objects;
drop policy if exists "nexora profiles update own" on storage.objects;
drop policy if exists "nexora profiles delete own" on storage.objects;

create policy "nexora profiles read" on storage.objects
  for select using (bucket_id = 'profiles');
create policy "nexora profiles insert own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'profiles' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "nexora profiles update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'profiles' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'profiles' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "nexora profiles delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'profiles' and (storage.foldername(name))[1] = auth.uid()::text);
