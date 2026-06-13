begin;
select plan(3);

select ok( exists(
  select 1 from pg_publication_tables
  where pubname='supabase_realtime' and schemaname='public' and tablename='trips'),
  'trips is in supabase_realtime publication');
select ok( exists(
  select 1 from pg_publication_tables
  where pubname='supabase_realtime' and schemaname='public' and tablename='trip_days'),
  'trip_days is in supabase_realtime publication');
select ok( exists(
  select 1 from pg_publication_tables
  where pubname='supabase_realtime' and schemaname='public' and tablename='trip_items'),
  'trip_items is in supabase_realtime publication');

select * from finish();
rollback;
