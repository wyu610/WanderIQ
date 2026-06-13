begin;
select plan(1);

insert into auth.users (id, email)
  values ('00000000-0000-0000-0000-0000000000a1', 'a@test.com');

-- Insert a row with a deliberately wrong server_updated_at far in the past;
-- the trigger must overwrite it to ~now(), not honor the client value.
with ins as (
  insert into trips (owner_id, name, server_updated_at)
  values ('00000000-0000-0000-0000-0000000000a1', 'T', '2000-01-01')
  returning server_updated_at)
select ok(
  (select server_updated_at from ins) > now() - interval '1 minute',
  'server_updated_at is stamped server-side, ignoring client value'
);

select * from finish();
rollback;
