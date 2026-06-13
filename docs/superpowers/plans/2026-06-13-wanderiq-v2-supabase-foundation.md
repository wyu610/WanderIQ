# WanderIQ v2 — Supabase Foundation Implementation Plan (cloud-first, no Docker)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the WanderIQ v2 backend as version-controlled Supabase migrations — schema, Row-Level Security, Realtime, profiles, and an Edge Function scaffold — developed directly against a hosted Supabase project (no local Docker), with pgTAP tests run over the wire via `psql`.

**Architecture:** No local container stack. A hosted Supabase project is the dev database. Migrations live in `supabase/migrations/*.sql` and are applied with `supabase db push`. Access rules are enforced by RLS policies backed by two `security definer` helper functions (`can_access_trip`, `can_edit_trip`); a `server_updated_at` trigger stamps every write so clients cannot spoof the sync cursor. pgTAP runs as a Supabase extension; a small `supabase/tests/run.sh` executes each transaction-wrapped (`begin … rollback`) test file with `psql` and fails on any `not ok` line. OAuth providers (Apple/Google) are configured last and are not needed to test the schema.

**Tech Stack:** Supabase (hosted, free tier), Supabase CLI (binary only — NOT Docker), PostgreSQL 15, pgTAP, `psql` (already present at `/opt/homebrew/opt/libpq/bin/psql`), Deno (bundled by the CLI for Edge Functions).

**Spec:** `docs/superpowers/specs/2026-06-13-wanderiq-v2-design.md` (sub-project 1 of §12; schema = §5, RLS = §5.2, sync columns/trigger = §6, Realtime = §6.6).

**Credentials:** The dev project's **Session-pooler** connection string lives in a gitignored `.env` as `SUPABASE_DB_URL` (session mode / port 5432 — supports `set role` and multi-statement transactions, unlike the transaction pooler on 6543). Never commit it.

**Execution model (read once, applies to every schema task 2–7):**
1. Write the pgTAP test file.
2. Run `./supabase/tests/run.sh` → expect the new file to FAIL (missing objects error or `not ok`).
3. Write the migration SQL.
4. `supabase db push` → applies the new migration to the cloud dev DB.
5. Run `./supabase/tests/run.sh` → expect ALL files PASS (cumulative regression).
6. Commit migration + test together.

Because there is no local `db reset`, migrations are forward-only; tests are transaction-wrapped so they never leave data behind. A separate production project (created later, never shared with the build session) will receive the same migrations via `db push`.

---

### Task 1: Cloud project, CLI, and test runner (USER provides project + connection string)

**Files:**
- Create: `supabase/config.toml` (via `supabase init`)
- Create: `supabase/tests/run.sh`
- Create: `.env.example`
- Modify: `.gitignore`

- [ ] **Step 1: USER — create the dev project and share credentials**

User action (cannot be automated): at https://supabase.com → New Project (free tier).
Then Project Settings → Database → **Connection string → "Session pooler" (URI)**.
Provide to the session: the **project ref** and that **Session-pooler URI** (it
contains the DB password — treated as a secret, stored only in gitignored `.env`).

- [ ] **Step 2: Install the Supabase CLI (binary, no container) and log in**

Run:
```bash
brew install supabase/tap/supabase
supabase --version          # expect 2.x.x
supabase login              # opens browser; authorize the CLI
```

- [ ] **Step 3: Initialize Supabase config and write `.env`**

Run (repo root):
```bash
supabase init               # answer N to VS Code/Deno prompts
```
Create `.env` (gitignored) with the values from Step 1:
```
SUPABASE_DB_URL=postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
```
Create `.env.example` (committed, no secrets):
```
# Session-pooler connection string for the dev Supabase project (port 5432).
SUPABASE_DB_URL=postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
```

- [ ] **Step 4: Link the CLI to the hosted project**

Run (user supplies the ref; CLI prompts for the DB password):
```bash
supabase link --project-ref <ref>
```
Expected: `Finished supabase link.`

- [ ] **Step 5: Enable pgTAP on the dev database (test-only, not a migration)**

Run:
```bash
source .env
/opt/homebrew/opt/libpq/bin/psql "$SUPABASE_DB_URL" -c \
  "create extension if not exists pgtap with schema extensions;"
```
Expected: `CREATE EXTENSION` (or no error if already present). pgTAP is kept out
of migrations so it never lands in the production schema.

- [ ] **Step 6: Write the test runner**

Create `supabase/tests/run.sh`:
```bash
#!/usr/bin/env bash
# Runs every *.test.sql against the cloud dev DB via psql and fails on `not ok`.
set -euo pipefail
[ -f .env ] && source .env
: "${SUPABASE_DB_URL:?set SUPABASE_DB_URL in .env}"
PSQL="${PSQL:-/opt/homebrew/opt/libpq/bin/psql}"
shopt -s nullglob
status=0
for f in supabase/tests/*.test.sql; do
  out=$("$PSQL" "$SUPABASE_DB_URL" -X -q -t -A -v ON_ERROR_STOP=1 -f "$f" 2>&1) || {
    echo "FAIL (error): $f"; echo "$out" | sed 's/^/    /'; status=1; continue; }
  if grep -q '^not ok' <<<"$out"; then
    echo "FAIL: $f"; grep -E '^(not ok|# )' <<<"$out" | sed 's/^/    /'; status=1
  else
    echo "PASS: $f ($(grep -c '^ok' <<<"$out") assertions)"
  fi
done
exit $status
```
Run: `chmod +x supabase/tests/run.sh`

- [ ] **Step 7: Add ignore rules and commit the scaffold**

Add to `.gitignore`:
```
# Supabase local secrets
.env
.env.*
!.env.example
supabase/.temp/
supabase/.branches/
```
Commit:
```bash
git add supabase/config.toml supabase/.gitignore supabase/tests/run.sh .env.example .gitignore
git commit -m "chore: cloud-first Supabase scaffold + psql pgTAP runner"
```

---

### Task 2: Core schema — enums, trips, days, items

**Files:**
- Create: `supabase/migrations/0001_core_schema.sql`
- Test: `supabase/tests/0001_schema.test.sql`

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/0001_schema.test.sql`:
```sql
begin;
select plan(8);

-- Tables exist
select has_table('public', 'trips',      'trips table exists');
select has_table('public', 'trip_days',  'trip_days table exists');
select has_table('public', 'trip_items', 'trip_items table exists');

-- Sync columns exist on trips
select has_column('public', 'trips', 'modified_at',       'trips.modified_at exists');
select has_column('public', 'trips', 'server_updated_at', 'trips.server_updated_at exists');
select has_column('public', 'trips', 'deleted',           'trips.deleted exists');

-- A real owner must exist (trips.owner_id references auth.users).
insert into auth.users (id, email)
  values ('00000000-0000-0000-0000-0000000000a1', 'a@test.com');

-- Defaults populate on insert (CTE form; no psql \gset meta-command).
with ins as (
  insert into trips (owner_id, name)
  values ('00000000-0000-0000-0000-0000000000a1', 'T')
  returning deleted)
select is( (select deleted from ins), false, 'deleted defaults false');

with ins as (
  insert into trips (owner_id, name)
  values ('00000000-0000-0000-0000-0000000000a1', 'T')
  returning server_updated_at)
select isnt( (select server_updated_at from ins), null, 'server_updated_at defaults now()');

select * from finish();
rollback;
```

> Note: `auth.users` may require additional NOT NULL columns on your Supabase
> version. If the insert errors, the message names the missing column — add it
> with a sane default (e.g. `instance_id`
> `'00000000-0000-0000-0000-000000000000'`, `aud`/`role` `'authenticated'`).
> This same minimal user-insert pattern is reused in later test files.

- [ ] **Step 2: Run the runner to verify it fails**

Run: `./supabase/tests/run.sh`
Expected: FAIL — `relation "trips" does not exist` (no migration pushed yet).

- [ ] **Step 3: Write the schema migration**

Create `supabase/migrations/0001_core_schema.sql`:
```sql
-- Enums
create type item_kind   as enum ('prep','hotel','doc','itinerary','packing');
create type member_role as enum ('viewer','editor');
create type member_status as enum ('pending','accepted');

-- trips
create table trips (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references auth.users(id) on delete cascade,
  name              text not null default '',
  start_date        date,
  end_date          date,
  destinations      text[] not null default '{}',
  schema_version    int  not null default 1,
  modified_at       timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted           boolean not null default false
);
create index trips_owner_idx on trips (owner_id);
create index trips_sru_idx   on trips (server_updated_at);

-- trip_days
create table trip_days (
  id                uuid primary key default gen_random_uuid(),
  trip_id           uuid not null references trips(id) on delete cascade,
  date              date,
  city              text not null default '',
  title             text not null default '',
  modified_at       timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted           boolean not null default false
);
create index trip_days_trip_idx on trip_days (trip_id);
create index trip_days_sru_idx  on trip_days (server_updated_at);

-- trip_items
create table trip_items (
  id                uuid primary key default gen_random_uuid(),
  trip_id           uuid not null references trips(id) on delete cascade,
  kind              item_kind not null,
  label             text not null default '',
  notes             text not null default '',
  day_id            uuid references trip_days(id) on delete set null,
  time              text,
  item_owner        text,
  is_done           boolean not null default false,
  sort_order        int not null default 0,
  reminder_date     timestamptz,
  place             jsonb,
  modified_at       timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  deleted           boolean not null default false
);
create index trip_items_trip_idx on trip_items (trip_id);
create index trip_items_day_idx  on trip_items (day_id);
create index trip_items_sru_idx  on trip_items (server_updated_at);
```

- [ ] **Step 4: Push the migration to the cloud DB**

Run: `supabase db push`
Expected: applies `0001_core_schema` with no error.

- [ ] **Step 5: Run the runner to verify it passes**

Run: `./supabase/tests/run.sh`
Expected: `PASS: supabase/tests/0001_schema.test.sql (8 assertions)`.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0001_core_schema.sql supabase/tests/0001_schema.test.sql
git commit -m "feat(db): core schema for trips, days, items"
```

---

### Task 3: `server_updated_at` trigger (clients cannot spoof the cursor)

**Files:**
- Create: `supabase/migrations/0002_server_updated_at.sql`
- Test: `supabase/tests/0002_trigger.test.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/0002_trigger.test.sql`:
```sql
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
```

- [ ] **Step 2: Run the runner to verify it fails**

Run: `./supabase/tests/run.sh`
Expected: FAIL — stored value is `2000-01-01` (no trigger yet), assertion false.

- [ ] **Step 3: Write the trigger migration**

Create `supabase/migrations/0002_server_updated_at.sql`:
```sql
create or replace function set_server_updated_at()
returns trigger language plpgsql as $$
begin
  new.server_updated_at = now();
  return new;
end;
$$;

create trigger trips_sru
  before insert or update on trips
  for each row execute function set_server_updated_at();

create trigger trip_days_sru
  before insert or update on trip_days
  for each row execute function set_server_updated_at();

create trigger trip_items_sru
  before insert or update on trip_items
  for each row execute function set_server_updated_at();
```

- [ ] **Step 4: Push and verify it passes**

Run:
```bash
supabase db push
./supabase/tests/run.sh
```
Expected: both test files PASS (0001 + 0002).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0002_server_updated_at.sql supabase/tests/0002_trigger.test.sql
git commit -m "feat(db): stamp server_updated_at on every write"
```

---

### Task 4: Members table + access-helper functions

**Files:**
- Create: `supabase/migrations/0003_members_and_access.sql`
- Test: `supabase/tests/0003_access.test.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/0003_access.test.sql`:
```sql
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
```

- [ ] **Step 2: Run the runner to verify it fails**

Run: `./supabase/tests/run.sh`
Expected: FAIL — `relation "trip_members" does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/0003_members_and_access.sql`:
```sql
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
```

- [ ] **Step 4: Push and verify it passes**

Run:
```bash
supabase db push
./supabase/tests/run.sh
```
Expected: 0001 + 0002 + 0003 all PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0003_members_and_access.sql supabase/tests/0003_access.test.sql
git commit -m "feat(db): trip_members table and access-helper functions"
```

---

### Task 5: Row-Level Security policies

**Files:**
- Create: `supabase/migrations/0004_rls.sql`
- Test: `supabase/tests/0004_rls.test.sql`

- [ ] **Step 1: Write the failing test (the core security safeguard)**

Create `supabase/tests/0004_rls.test.sql`:
```sql
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
```

- [ ] **Step 2: Run the runner to verify it fails**

Run: `./supabase/tests/run.sh`
Expected: FAIL — with RLS disabled, B sees A's trip (counts are 1, not 0).

- [ ] **Step 3: Write the RLS migration**

Create `supabase/migrations/0004_rls.sql`:
```sql
alter table trips        enable row level security;
alter table trip_days    enable row level security;
alter table trip_items   enable row level security;
alter table trip_members enable row level security;

-- trips: owner or any member reads; owner-only writes the trip row.
create policy trips_select on trips for select
  using (owner_id = auth.uid() or can_access_trip(id));
create policy trips_insert on trips for insert
  with check (owner_id = auth.uid());
create policy trips_update on trips for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy trips_delete on trips for delete
  using (owner_id = auth.uid());

-- trip_days: read if access; write if owner or editor.
create policy days_select on trip_days for select
  using (can_access_trip(trip_id));
create policy days_write on trip_days for all
  using (can_edit_trip(trip_id)) with check (can_edit_trip(trip_id));

-- trip_items: same rule as days.
create policy items_select on trip_items for select
  using (can_access_trip(trip_id));
create policy items_write on trip_items for all
  using (can_edit_trip(trip_id)) with check (can_edit_trip(trip_id));

-- trip_members: members read the list; only the trip owner manages members.
create policy members_select on trip_members for select
  using (can_access_trip(trip_id));
create policy members_manage on trip_members for all
  using (exists (select 1 from trips t
                 where t.id = trip_id and t.owner_id = auth.uid()))
  with check (exists (select 1 from trips t
                 where t.id = trip_id and t.owner_id = auth.uid()));
```

> Design note (matches spec §5.2): editors may edit days/items (content) but
> NOT the trip row itself — renaming/deleting a trip and managing members are
> owner-only. Tombstone deletes are `update ... set deleted = true`, governed
> by the `*_write` / `trips_update` policies above, not the `delete` policy.

- [ ] **Step 4: Push and verify it passes**

Run:
```bash
supabase db push
./supabase/tests/run.sh
```
Expected: 0001–0004 all PASS (7 assertions in 0004).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0004_rls.sql supabase/tests/0004_rls.test.sql
git commit -m "feat(db): row-level security policies for trips, days, items, members"
```

---

### Task 6: Realtime publication

**Files:**
- Create: `supabase/migrations/0005_realtime.sql`
- Test: `supabase/tests/0005_realtime.test.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/0005_realtime.test.sql`:
```sql
begin;
select plan(3);

select ok( exists(
  select 1 from pg_publication_tables
  where pubname='supabase_realtime' and schemaname='public' and tablename='trips'),
  'trips is in supabase_realtime publication');
select ok( exists(
  select 1 from pg_publication_tables
  where pubname='supabase_realtime' and schemaname='public' and tablename='trip_days'),
  'trip_days is in supabase_realtime publication');
select ok( exists(
  select 1 from pg_publication_tables
  where pubname='supabase_realtime' and schemaname='public' and tablename='trip_items'),
  'trip_items is in supabase_realtime publication');

select * from finish();
rollback;
```

- [ ] **Step 2: Run the runner to verify it fails**

Run: `./supabase/tests/run.sh`
Expected: FAIL — tables not yet in the publication.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/0005_realtime.sql`:
```sql
-- The supabase_realtime publication is created by the platform; add our
-- syncable tables so clients receive change events (spec §6.6).
alter publication supabase_realtime add table trips;
alter publication supabase_realtime add table trip_days;
alter publication supabase_realtime add table trip_items;
```

- [ ] **Step 4: Push and verify it passes**

Run:
```bash
supabase db push
./supabase/tests/run.sh
```
Expected: 0001–0005 all PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0005_realtime.sql supabase/tests/0005_realtime.test.sql
git commit -m "feat(db): publish trips/days/items to Realtime"
```

---

### Task 7: `profiles` table + auto-insert on signup

**Files:**
- Create: `supabase/migrations/0006_profiles.sql`
- Test: `supabase/tests/0006_profiles.test.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/0006_profiles.test.sql`:
```sql
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
```

- [ ] **Step 2: Run the runner to verify it fails**

Run: `./supabase/tests/run.sh`
Expected: FAIL — `relation "profiles" does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/0006_profiles.sql`:
```sql
create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now()
);

alter table profiles enable row level security;
-- Any authenticated user may read profiles (to show who shared/owns a trip);
-- a user may update only their own.
create policy profiles_select on profiles for select using (auth.role() = 'authenticated');
create policy profiles_update on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- Auto-create a profile when an auth user is created.
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
```

- [ ] **Step 4: Push and verify it passes**

Run:
```bash
supabase db push
./supabase/tests/run.sh
```
Expected: 0001–0006 all PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0006_profiles.sql supabase/tests/0006_profiles.test.sql
git commit -m "feat(db): profiles table with auto-insert on signup"
```

---

### Task 8: Edge Function scaffold (health check)

**Files:**
- Create: `supabase/functions/health/index.ts`

This proves the Edge Function deploy pipeline early. The real invite-email
function is built in sub-project 5 (Sharing).

- [ ] **Step 1: Write the function**

Create `supabase/functions/health/index.ts`:
```ts
// Minimal Edge Function to verify the deploy pipeline.
// Sub-project 5 adds the invite-email function alongside this.
Deno.serve((_req: Request) => {
  return new Response(
    JSON.stringify({ status: "ok", service: "wanderiq" }),
    { headers: { "Content-Type": "application/json" } },
  );
});
```

- [ ] **Step 2: Deploy and verify it responds**

Run (the CLI bundles Deno; no separate Deno install needed):
```bash
supabase functions deploy health --no-verify-jwt
source .env
# Derive the project URL from the ref, or read it from `supabase status` output.
curl -s "https://<ref>.supabase.co/functions/v1/health"
```
Expected: `{"status":"ok","service":"wanderiq"}`.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/health/index.ts
git commit -m "feat(functions): health-check Edge Function scaffold"
```

---

### Task 9: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Confirm migrations are fully applied and tests green**

Run:
```bash
supabase migration list      # local list 0001..0006 all marked applied to remote
./supabase/tests/run.sh
```
Expected: `migration list` shows `0001`…`0006` applied on the remote column;
runner prints `PASS` for all six test files (8 + 1 + 5 + 7 + 3 + 2 = 26 assertions).

- [ ] **Step 2: Commit any fixes** (only if Step 1 surfaced issues)

```bash
git add -A && git commit -m "fix(db): resolve issues found in full verification pass"
```

---

### Task 10: OAuth providers (USER ACTION — deferrable until client auth)

**Files:** none

The schema/RLS foundation is fully testable with the default email provider.
Apple/Google OAuth is only needed once a client signs in (sub-projects 3–4), so
this task may be done now or deferred — it does not block sub-project 2.

- [ ] **Step 1: User configures providers in the dashboard**

User action — Supabase dashboard → Authentication → Providers:
- **Email**: enabled (default) — nothing to do.
- **Apple**: enable; supply the Services ID, Team ID, Key ID, and `.p8` key from
  the Apple Developer account; set the redirect URL Supabase shows.
- **Google**: enable; supply the OAuth client ID + secret from Google Cloud
  Console; set the redirect URL Supabase shows.

(These secrets are entered only in the dashboard — nothing to commit.)

---

## Done criteria

- `./supabase/tests/run.sh` passes all six test files against the cloud dev DB.
- Schema, trigger, members + access helpers, RLS, Realtime, profiles, and a
  health Edge Function are version-controlled migrations applied via `db push`.
- `SUPABASE_DB_URL` lives only in gitignored `.env`; `.env.example` is committed.
- OAuth providers configured when convenient (Task 10; not a blocker).
- Next plan: **sub-project 2 — sync protocol contract + iOS Swift sync engine.**
