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
