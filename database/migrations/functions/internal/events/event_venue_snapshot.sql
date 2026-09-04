-- Captures the venue address of an event as the snapshot stored with tax
-- locations and purchases. Blank fields are stored as nulls.
create or replace function event_venue_snapshot(p_event event)
returns jsonb as $$
    select jsonb_build_object(
        'address', nullif(btrim(p_event.venue_address), ''),
        'city', nullif(btrim(p_event.venue_city), ''),
        'country_code', nullif(btrim(p_event.venue_country_code), ''),
        'name', nullif(btrim(p_event.venue_name), ''),
        'state_code', nullif(btrim(p_event.venue_state_code), ''),
        'state_name', nullif(btrim(p_event.venue_state_name), ''),
        'zip_code', nullif(btrim(p_event.venue_zip_code), '')
    );
$$ language sql immutable;
