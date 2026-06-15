begin;
select plan(4);

select has_function('public', 'claim_invites', 'claim_invites() exists');

-- Owner A, trip T, a pending editor invite for b@test.com, and user B (that email).
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'b@test.com');
insert into trips (id, owner_id, name)
  values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a1', 'Trip');
insert into trip_members (trip_id, invited_email, role, status)
  values ('00000000-0000-0000-0000-0000000000f1', 'B@test.com', 'editor', 'pending');

-- Act as user B and claim.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2"}';
select is( claim_invites(), 1, 'B claims one pending invite (case-insensitive email)');

-- The membership is now linked + accepted.
set local role postgres;
select is(
  (select count(*) from trip_members
   where user_id = '00000000-0000-0000-0000-0000000000b2'
     and status = 'accepted')::int,
  1, 'invite linked to B and accepted');

-- B can now see the trip under RLS.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2"}';
select is( (select count(*) from trips
            where id = '00000000-0000-0000-0000-0000000000f1')::int,
           1, 'RLS now grants B access to the shared trip');

select * from finish();
rollback;
