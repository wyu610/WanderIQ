-- The supabase_realtime publication is created by the platform; add our
-- syncable tables so clients receive change events (spec §6.6).
alter publication supabase_realtime add table trips;
alter publication supabase_realtime add table trip_days;
alter publication supabase_realtime add table trip_items;
