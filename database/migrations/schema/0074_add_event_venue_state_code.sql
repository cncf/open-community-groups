-- Separates event subdivision display names from ISO subdivision codes.

alter table event rename column venue_state to venue_state_name;

alter table event
add column venue_state_code text check (btrim(venue_state_code) <> '');
