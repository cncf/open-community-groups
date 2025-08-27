-- update_event updates an existing event in the database.
create or replace function update_event(
    p_group_id uuid,
    p_event_id uuid,
    p_event jsonb
)
returns void as $$
declare
    v_timezone_abbr text;
begin
    -- Look up timezone abbreviation
    select abbrev into v_timezone_abbr
    from pg_timezone_names
    where name = p_event->>'timezone';
    if v_timezone_abbr is null then
        raise exception 'Invalid timezone: %', p_event->>'timezone';
    end if;

    update event set
        name = p_event->>'name',
        slug = p_event->>'slug',
        description = p_event->>'description',
        timezone = p_event->>'timezone',
        event_category_id = (p_event->>'category_id')::uuid,
        event_kind_id = p_event->>'kind_id',

        banner_url = p_event->>'banner_url',
        capacity = (p_event->>'capacity')::int,
        description_short = p_event->>'description_short',
        ends_at = (p_event->>'ends_at')::timestamp at time zone (p_event->>'timezone'),
        logo_url = p_event->>'logo_url',
        meetup_url = p_event->>'meetup_url',
        photos_urls = case when p_event->'photos_urls' is not null then array(select jsonb_array_elements_text(p_event->'photos_urls')) else null end,
        recording_url = p_event->>'recording_url',
        registration_required = (p_event->>'registration_required')::boolean,
        starts_at = (p_event->>'starts_at')::timestamp at time zone (p_event->>'timezone'),
        streaming_url = p_event->>'streaming_url',
        tags = case when p_event->'tags' is not null then array(select jsonb_array_elements_text(p_event->'tags')) else null end,
        timezone_abbr = v_timezone_abbr,
        venue_address = p_event->>'venue_address',
        venue_city = p_event->>'venue_city',
        venue_name = p_event->>'venue_name',
        venue_zip_code = p_event->>'venue_zip_code'
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false;

    if not found then
        raise exception 'event not found';
    end if;
end;
$$ language plpgsql;
