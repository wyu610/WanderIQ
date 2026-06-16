begin;
select plan(4);

select has_function('public', 'delete_my_account', 'delete_my_account() exists');

-- User A owns trip T; user B is an accepted editor member of T.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@test.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'b@test.com');
insert into trips (id, owner_id, name)
  values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a1', 'Trip');
insert into trip_members (trip_id, user_id, role, status)
  values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b2', 'editor', 'accepted');

-- Act as A and delete the account.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1"}';
select lives_ok($$ select delete_my_account() $$, 'A deletes their own account');

-- A's auth row is gone, and the owned trip (with its member rows) cascaded away.
set local role postgres;
select is( (select count(*) from auth.users
            where id = '00000000-0000-0000-0000-0000000000a1')::int,
           0, 'auth.users row removed');
select is( (select count(*) from trips
            where id = '00000000-0000-0000-0000-0000000000f1')::int,
           0, 'owned trip cascade-deleted (days/items/members gone with it)');

select * from finish();
rollback;
