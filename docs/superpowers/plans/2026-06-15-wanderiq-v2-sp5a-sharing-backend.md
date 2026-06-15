# WanderIQ v2 — Sub-project 5a: Sharing Backend (email-match claim)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable per-trip sharing by email with viewer/editor roles using the existing `trip_members` table — add a `claim_invites()` function that links a signing-in user to pending invites matching their email, and verify the full owner-add → claim → access flow with pgTAP.

**Architecture:** No schema change — `trip_members(trip_id, user_id, role, invited_email, status)` and the RLS from sub-project 1 already exist. The owner adds a member by inserting a `pending` row with `invited_email` + role (allowed by the existing `members_manage` policy). The invitee can't update that row under RLS (only the owner can), so a `security definer` `claim_invites()` function links `user_id = auth.uid()` + `status = 'accepted'` for pending rows whose `invited_email` matches the caller's `auth.users.email` (case-insensitive). Clients call it via `supabase.rpc('claim_invites')` after sign-in; the existing `can_access_trip` RLS then grants the trip. Tested with pgTAP against the live cloud dev DB (the sub-project-1 `supabase/tests/run.sh` harness).

**Tech Stack:** PostgreSQL, pgTAP, psql (`/opt/homebrew/opt/libpq/bin/psql`), `SUPABASE_DB_URL` from the gitignored `.env`.

**Spec:** design §9.1 (sharing: per-trip email invite + viewer/editor roles). Backend half; iOS UI = 5b, web UI = 5c.

**Prerequisite:** the existing `.env` with `SUPABASE_DB_URL` (already present from sub-project 1). Migrations 0001–0006 are already applied to the dev DB.

**Verification:** `./supabase/tests/run.sh` (all pgTAP files green, including the new sharing tests).

---

### Task 1: `claim_invites()` function

**Files:**
- Create: `supabase/migrations/0007_claim_invites.sql`
- Test: `supabase/tests/0007_claim.test.sql`

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/0007_claim.test.sql`:
```sql
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `./supabase/tests/run.sh`
Expected: FAIL — `function claim_invites() does not exist` (and the dependent assertions error).

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/0007_claim_invites.sql`:
```sql
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
```

- [ ] **Step 4: Apply + verify it passes**

Run:
```bash
cd /Users/wyu610/_Dev/WanderIQ
source .env
/opt/homebrew/opt/libpq/bin/psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/0007_claim_invites.sql
./supabase/tests/run.sh
```
Expected: `CREATE FUNCTION` / `GRANT`; runner reports all test files PASS, including `0007_claim.test.sql` (4 assertions).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0007_claim_invites.sql supabase/tests/0007_claim.test.sql
git commit -m "feat(db): claim_invites() links email invites to the signing-in user"
```

---

### Task 2: Owner-add + member-list RLS verification

**Files:**
- Test: `supabase/tests/0008_sharing_rls.test.sql`

Confirms the flows the 5b/5c UIs rely on, all under the existing RLS: the owner
can add a pending invite; owner + accepted members can read the member list; a
viewer cannot edit content but an editor can; a non-member sees nothing.

- [ ] **Step 1: Write the test**

Create `supabase/tests/0008_sharing_rls.test.sql`:
```sql
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
```

- [ ] **Step 2: Run to verify it passes**

Run: `./supabase/tests/run.sh`
Expected: PASS — `0008_sharing_rls.test.sql` (6 assertions) green, confirming the
existing RLS already enforces the full owner/viewer/editor/stranger matrix the UI
will depend on. (This test needs no new migration — it validates sub-project 1's
policies in the sharing context.)

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/0008_sharing_rls.test.sql
git commit -m "test(db): verify sharing RLS (owner add, viewer/editor, stranger)"
```

---

## Done criteria

- `./supabase/tests/run.sh` passes all files including `0007_claim` (4) and
  `0008_sharing_rls` (6).
- `claim_invites()` is deployed to the dev DB and grant-restricted to
  `authenticated`.
- The owner-add / claim / role-enforced-access flow is proven end-to-end in SQL.
- Next: **5b** — iOS share UI (a sheet to add a member by email + role, list/
  remove members; call `claim_invites` on launch; re-add the trip-detail share
  button removed in 3c). Then **5c** — the web share UI (same, in Preact).

## Notes for 5b / 5c

- Add member: client `insert` into `trip_members` `{trip_id, invited_email, role,
  status:'pending'}` (owner-gated by RLS).
- List members: `select * from trip_members where trip_id = …` (returns rows the
  user may see per RLS) — join `profiles` for display names/emails of accepted
  members.
- On sign-in (both clients): `supabase.rpc('claim_invites')`, then a sync pull so
  newly-granted trips appear.
- Optional later enhancement: an invite-notification email via an Edge Function
  (deferred per the chosen email-match mechanism).
