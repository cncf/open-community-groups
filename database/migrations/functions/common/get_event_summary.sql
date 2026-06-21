-- Returns summary information about an event.
create or replace function get_event_summary(
    p_alliance_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    -- Build event summary payload
    select json_strip_nulls(json_build_object(
        -- Include core summary fields
        'canceled', e.canceled,
        'alliance_display_name', c.display_name,
        'alliance_name', c.name,
        'event_id', e.event_id,
        'group_category_name', gc.name,
        'group_name', g.name,
        'group_slug', g.slug,
        'has_registration_questions', jsonb_array_length(coalesce(e.registration_questions, '[]'::jsonb)) > 0,
        'has_related_events', exists (
            select 1
            from event related_event
            where related_event.event_series_id = e.event_series_id
            and related_event.event_id <> e.event_id
            and related_event.deleted = false
        ),
        'kind', e.event_kind_id,
        'name', e.name,
        'published', e.published,
        'slug', e.slug,
        'test_event', e.test_event,
        'timezone', e.timezone,

        -- Include optional event details
        'attendee_approval_required', e.attendee_approval_required,
        'capacity', e.capacity,
        'description_short', e.description_short,
        'ends_at', floor(extract(epoch from e.ends_at)),
        'event_series_id', e.event_series_id,
        'group_slug_pretty', g.slug_pretty,
        'latitude', st_y(e.location::geometry),
        'logo_url', coalesce(e.logo_url, g.logo_url, c.logo_url),
        'longitude', st_x(e.location::geometry),
        'meeting_join_instructions', e.meeting_join_instructions,
        'meeting_join_url', coalesce(m_event.join_url, e.meeting_join_url),
        'meeting_password', m_event.password,
        'meeting_provider', e.meeting_provider_id,
        'payment_currency_code', e.payment_currency_code,
        'starts_at', floor(extract(epoch from e.starts_at)),
        'ticket_types', list_event_ticket_types(e.event_id),
        'venue_address', e.venue_address,
        'venue_city', e.venue_city,
        'venue_country_code', e.venue_country_code,
        'venue_country_name', e.venue_country_name,
        'venue_name', e.venue_name,
        'venue_state', e.venue_state,
        'waitlist_count', coalesce(ew.waitlist_count, 0),
        'waitlist_enabled', e.waitlist_enabled,
        'zip_code', e.venue_zip_code,

        -- Include computed capacity values
        'remaining_capacity',
            case
                when e.capacity is null then null
                else greatest(e.capacity - coalesce(ea.attendee_count, 0), 0)
            end
    )) as json_data
    from event e
    join "group" g using (group_id)
    join alliance c on c.alliance_id = g.alliance_id
    join group_category gc on g.group_category_id = gc.group_category_id
    left join meeting m_event on m_event.event_id = e.event_id
    cross join lateral get_event_occupied_seat_count(e.event_id) as ea(attendee_count)
    cross join lateral (
        select count(*)::int as waitlist_count
        from event_waitlist ewl
        where ewl.event_id = e.event_id
    ) ew
    where e.event_id = p_event_id
    and g.group_id = p_group_id
    and g.alliance_id = p_alliance_id;
$$ language sql;
