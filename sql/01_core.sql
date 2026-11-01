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
