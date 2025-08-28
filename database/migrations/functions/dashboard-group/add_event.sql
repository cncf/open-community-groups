-- add_event adds a new event to the database.
create or replace function add_event(
    p_group_id uuid,
    p_event jsonb
)
returns uuid as $$
    insert into event (
        group_id,
        name,
        slug,
        description,
        timezone,
        event_category_id,
        event_kind_id,

        banner_url,
        capacity,
        description_short,
        ends_at,
        logo_url,
        meetup_url,
        photos_urls,
        recording_url,
        registration_required,
        starts_at,
        streaming_url,
        tags,
        venue_address,
        venue_city,
        venue_name,
        venue_zip_code
    ) values (
        p_group_id,
        p_event->>'name',
        p_event->>'slug',
        p_event->>'description',
        p_event->>'timezone',
        (p_event->>'category_id')::uuid,
        p_event->>'kind_id',

        p_event->>'banner_url',
        (p_event->>'capacity')::int,
        p_event->>'description_short',
        (p_event->>'ends_at')::timestamp at time zone (p_event->>'timezone'),
        p_event->>'logo_url',
        p_event->>'meetup_url',
        case when p_event->'photos_urls' is not null then array(select jsonb_array_elements_text(p_event->'photos_urls')) else null end,
        p_event->>'recording_url',
        (p_event->>'registration_required')::boolean,
        (p_event->>'starts_at')::timestamp at time zone (p_event->>'timezone'),
        p_event->>'streaming_url',
        case when p_event->'tags' is not null then array(select jsonb_array_elements_text(p_event->'tags')) else null end,
        p_event->>'venue_address',
        p_event->>'venue_city',
        p_event->>'venue_name',
        p_event->>'venue_zip_code'
    )
    returning event_id
$$ language sql;