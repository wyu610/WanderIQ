begin;
select plan(8);

-- Tables exist
select has_table('public', 'trips',      'trips table exists');
select has_table('public', 'trip_days',  'trip_days table exists');
select has_table('public', 'trip_items', 'trip_items table exists');

-- Sync columns exist on trips
select has_column('public', 'trips', 'modified_at',       'trips.modified_at exists');
select has_column('public', 'trips', 'server_updated_at', 'trips.server_updated_at exists');
select has_column('public', 'trips', 'deleted',           'trips.deleted exists');

-- A real owner must exist (trips.owner_id references auth.users).
insert into auth.users (id, email)
  values ('00000000-0000-0000-0000-0000000000a1', 'a@test.com');

-- Defaults populate on insert (CTE form; no psql \gset meta-command).
with ins as (
  insert into trips (owner_id, name)
  values ('00000000-0000-0000-0000-0000000000a1', 'T')
  returning deleted)
select is( (select deleted from ins), false, 'deleted defaults false');

with ins as (
  insert into trips (owner_id, name)
  values ('00000000-0000-0000-0000-0000000000a1', 'T')
  returning server_updated_at)
select isnt( (select server_updated_at from ins), null, 'server_updated_at defaults now()');

select * from finish();
rollback;
