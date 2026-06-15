begin;
select plan(6);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'viewer@test.com'),
  ('00000000-0000-0000-0000-0000000000c3', 'editor@test.com'),
  ('00000000-0000-0000-0000-0000000000d4', 'stranger@test.com');

-- Owner A creates a trip and adds two members (under members_manage RLS).
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1"}';
insert into trips (id, owner_id, name)
  values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a1', 'Trip');
insert into trip_members (trip_id, user_id, role, status) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b2', 'viewer', 'accepted'),
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000c3', 'editor', 'accepted');
select is( (select count(*) from trip_members
            where trip_id = '00000000-0000-0000-0000-0000000000f1')::int,
           2, 'owner can add members and read the list');

-- Viewer: reads the member list, reads the trip, but CANNOT write content.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2"}';
select is( (select count(*) from trip_members
            where trip_id = '00000000-0000-0000-0000-0000000000f1')::int,
           2, 'viewer reads the member list');
select is( (select count(*) from trips
            where id = '00000000-0000-0000-0000-0000000000f1')::int, 1, 'viewer reads the trip');
select throws_like(
  $$insert into trip_items (trip_id, kind, label)
    values ('00000000-0000-0000-0000-0000000000f1', 'prep', 'X')$$,
  '%row-level security%', 'viewer cannot write content');

-- Editor: CAN write content.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c3"}';
insert into trip_items (trip_id, kind, label)
  values ('00000000-0000-0000-0000-0000000000f1', 'prep', 'Buy');
select is( (select count(*) from trip_items
            where trip_id = '00000000-0000-0000-0000-0000000000f1')::int, 1, 'editor can write content');

-- Stranger: sees nothing.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d4"}';
select is( (select count(*) from trips
            where id = '00000000-0000-0000-0000-0000000000f1')::int, 0, 'stranger sees no shared trip');

select * from finish();
rollback;
