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
