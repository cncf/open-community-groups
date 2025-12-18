-- Add venue country and state columns to event table.
alter table event add column venue_country_code text check (btrim(venue_country_code) <> '');
alter table event add column venue_country_name text check (btrim(venue_country_name) <> '');
alter table event add column venue_state text check (btrim(venue_state) <> '');
