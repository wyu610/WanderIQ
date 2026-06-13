begin;
select plan(5);

select has_table('public', 'trip_members', 'trip_members table exists');
select has_function('public', 'can_access_trip', array['uuid'], 'can_access_trip(uuid) exists');
select has_function('public', 'can_edit_trip',   array['uuid'], 'can_edit_trip(uuid) exists');

-- Duplicate accepted member (same user, same trip) is rejected by partial unique index.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'member@test.com');
insert into trips (id, owner_id, name)
  values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a1', 'Trip');
insert into trip_members (trip_id, user_id, role, status)
  values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b2', 'editor', 'accepted');

select throws_ok(
  $$insert into trip_members (trip_id, user_id, role, status)
    values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000b2','viewer','accepted')$$,
  '23505',
  null,
  'duplicate (trip_id, user_id) member rejected'
);

-- Two pending invites to the same email on one trip are rejected too.
insert into trip_members (trip_id, invited_email, role, status)
  values ('00000000-0000-0000-0000-0000000000f1', 'Friend@test.com', 'viewer', 'pending');
select throws_ok(
  $$insert into trip_members (trip_id, invited_email, role, status)
    values ('00000000-0000-0000-0000-0000000000f1','friend@test.com','editor','pending')$$,
  '23505',
  null,
  'duplicate invited_email (case-insensitive) rejected'
);

select * from finish();
rollback;
