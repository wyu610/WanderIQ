create table trip_members (
  id            uuid primary key default gen_random_uuid(),
  trip_id       uuid not null references trips(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete cascade,
  role          member_role not null default 'viewer',
  invited_email text,
  status        member_status not null default 'pending',
  created_at    timestamptz not null default now()
);
create unique index trip_members_user_uniq
  on trip_members (trip_id, user_id) where user_id is not null;
create unique index trip_members_email_uniq
  on trip_members (trip_id, lower(invited_email)) where invited_email is not null;
create index trip_members_user_idx on trip_members (user_id);

-- Access helpers. security definer so they bypass RLS on the tables they read
-- (avoids recursive policy evaluation). search_path pinned for safety.
create or replace function can_access_trip(p_trip_id uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (select 1 from trips t
                 where t.id = p_trip_id and t.owner_id = auth.uid())
      or exists (select 1 from trip_members m
                 where m.trip_id = p_trip_id
                   and m.user_id = auth.uid()
                   and m.status = 'accepted');
$$;

create or replace function can_edit_trip(p_trip_id uuid)
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (select 1 from trips t
                 where t.id = p_trip_id and t.owner_id = auth.uid())
      or exists (select 1 from trip_members m
                 where m.trip_id = p_trip_id
                   and m.user_id = auth.uid()
                   and m.status = 'accepted'
                   and m.role = 'editor');
$$;
