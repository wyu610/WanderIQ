begin;
select plan(2);

select has_table('public', 'profiles', 'profiles table exists');

-- Inserting an auth user fires the trigger that creates a profile row.
insert into auth.users (id, email)
  values ('00000000-0000-0000-0000-0000000000c3', 'c@test.com');
select is(
  (select count(*) from profiles where id = '00000000-0000-0000-0000-0000000000c3')::int,
  1, 'profile auto-created on new auth user');

select * from finish();
rollback;
