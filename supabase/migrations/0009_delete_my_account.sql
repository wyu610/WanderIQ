-- delete_my_account(): a signed-in user permanently deletes their OWN account.
-- Deleting the auth.users row cascades — trips.owner_id, trip_members.user_id,
-- and profiles.id all reference auth.users ON DELETE CASCADE (and trips cascade
-- to trip_days/trip_items) — so every trace of the user is removed. SECURITY
-- DEFINER so it may delete from auth.users; it only ever deletes the caller's
-- own row (auth.uid()). Required for App Store guideline 5.1.1(v) (in-app
-- account deletion) and surfaced as "Delete Account" in both clients.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
