begin;
select plan(7);

-- Seed two users; A owns a trip, B has no access yet.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1','a@test.com'),
  ('00000000-0000-0000-0000-0000000000b2','b@test.com');

-- Act as user A (authenticated role + JWT sub claim drive auth.uid()).
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1"}';

insert into trips (id, owner_id, name)
  values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000a1','A trip');
select is( (select count(*) from trips)::int, 1, 'A sees own trip');

insert into trip_days (id, trip_id, city)
  values ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000000f1','SH');
select is( (select count(*) from trip_days)::int, 1, 'A sees own day');

-- Switch to user B: must see nothing.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2"}';
select is( (select count(*) from trips)::int,     0, 'B cannot see A trip');
select is( (select count(*) from trip_days)::int, 0, 'B cannot see A day');

-- B cannot write into A's trip.
select throws_like(
  $$insert into trip_days (trip_id, city)
    values ('00000000-0000-0000-0000-0000000000f1','HK')$$,
  '%row-level security%',
  'B cannot insert a day into A trip'
);

-- Grant B viewer access (as postgres, the table owner, bypassing RLS).
set local role postgres;
insert into trip_members (trip_id, user_id, role, status)
  values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000b2','viewer','accepted');

-- B now reads but still cannot write (viewer, not editor).
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2"}';
select is( (select count(*) from trips)::int, 1, 'viewer B now sees the trip');
select throws_like(
  $$insert into trip_days (trip_id, city)
    values ('00000000-0000-0000-0000-0000000000f1','HK')$$,
  '%row-level security%',
  'viewer B still cannot write'
);

select * from finish();
rollback;
