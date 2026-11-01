-- Nexora card expansion v1
-- Additive migration: does not reset collections, card serials, player balances or inventory.
insert into public.card_defs (id,name,rarity,element,image,blurb,base_price,active) values
('common-09','Astra Wisp','common','celestial','assets/cards/common-09.svg','A tiny star spirit that collects forgotten wishes.',10,true),
('uncommon-02','Moonveil Lynx','uncommon','celestial','assets/cards/uncommon-02.svg','A silent guardian that walks between moonbeams.',40,true),
('rare-01','Astral Stag','rare','celestial','assets/cards/rare-01.svg','Its antlers map constellations no mortal has seen.',150,true),
('epic-01','Oracle of Dawn','epic','celestial','assets/cards/epic-01.svg','She reads tomorrow in the first light of a new sun.',600,true),
('celestial-01','Eclipsera','celestial','celestial','assets/cards/celestial-01.svg','The living eclipse, keeper of the cosmic threshold.',3000,true),
('common-10','Cinderling','common','ember','assets/cards/common-10.svg','A cheerful spark with a talent for tiny explosions.',10,true),
('common-11','Ash Hopper','common','ember','assets/cards/common-11.svg','Leaps through hot coals without singeing a whisker.',10,true),
('uncommon-03','Ashfang','uncommon','ember','assets/cards/uncommon-03.svg','A young drake whose breath turns stone to glass.',40,true),
('rare-02','Pyrewing','rare','ember','assets/cards/rare-02.svg','A phoenix-born hunter that never lands twice.',150,true),
('epic-02','Inferno Sovereign','epic','ember','assets/cards/epic-02.svg','An ancient ruler crowned by a storm of living flame.',600,true),
('common-12','Ripplefin','common','tide','assets/cards/common-12.svg','A curious little swimmer that follows every bubble.',10,true),
('uncommon-04','Pearlwarden','uncommon','tide','assets/cards/uncommon-04.svg','A patient sentinel protecting the hidden reef gates.',40,true),
('uncommon-05','Coral Dancer','uncommon','tide','assets/cards/coral-dancer.svg','Moves with the current and leaves gardens in its wake.',40,true),
('rare-03','Abyssal Leviathan','rare','tide','assets/cards/rare-03.svg','A deep-sea titan whose shadow quiets the ocean.',150,true),
('epic-03','Tidemother','epic','tide','assets/cards/epic-03.svg','The first wave, said to have shaped every living shore.',600,true),
('common-13','Gloomkin','common','void','assets/cards/common-13.svg','A shy shadow that borrows shapes from passing dreams.',10,true),
('common-14','Null Mote','common','void','assets/cards/common-14.svg','A tiny anomaly that makes nearby candles flicker.',10,true),
('uncommon-06','Rift Stalker','uncommon','void','assets/cards/uncommon-06.svg','Tracks lost things through cracks between worlds.',40,true),
('uncommon-07','Dusk Harrier','uncommon','void','assets/cards/dusk-harrier.svg','A silent hunter that circles the edge of reality.',40,true),
('rare-04','Null Raven','rare','void','assets/cards/rare-04.svg','Carries messages from places that no longer exist.',150,true)
on conflict (id) do update set name=excluded.name, rarity=excluded.rarity, element=excluded.element,
 image=excluded.image, blurb=excluded.blurb, base_price=excluded.base_price, active=true;
