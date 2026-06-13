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
