-- Link the signing-in user to any pending invites addressed to their email.
-- security definer so it can update trip_members rows the invitee cannot yet
-- touch under RLS (only the trip owner can). auth.uid() still resolves to the
-- caller (it reads the request JWT, not the definer). Returns rows claimed.
create or replace function claim_invites()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_count integer;
begin
  select email into v_email from auth.users where id = auth.uid();
  if v_email is null then
    return 0;
  end if;
  update trip_members
     set user_id = auth.uid(), status = 'accepted'
   where user_id is null
     and status = 'pending'
     and lower(invited_email) = lower(v_email);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function claim_invites() from public;
grant execute on function claim_invites() to authenticated;
