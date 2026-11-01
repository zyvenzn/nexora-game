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
