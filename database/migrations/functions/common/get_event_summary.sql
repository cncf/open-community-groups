-- Returns summary information about an event.
create or replace function get_event_summary(
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    select json_strip_nulls(json_build_object(
        'canceled', e.canceled,
        'community_display_name', c.display_name,
        'community_name', c.name,
        'event_id', e.event_id,
        'group_category_name', gc.name,
        'group_name', g.name,
        'group_slug', g.slug,
        'kind', e.event_kind_id,
        'name', e.name,
        'published', e.published,
        'slug', e.slug,
        'timezone', e.timezone,

        'capacity', e.capacity,
        'description_short', e.description_short,
        'ends_at', floor(extract(epoch from e.ends_at)),
        'latitude', st_y(e.location::geometry),
        'logo_url', coalesce(e.logo_url, g.logo_url),
        'longitude', st_x(e.location::geometry),
        'meeting_join_url', coalesce(m_event.join_url, e.meeting_join_url),
        'meeting_password', m_event.password,
        'meeting_provider', e.meeting_provider_id,
        'starts_at', floor(extract(epoch from e.starts_at)),
        'venue_address', e.venue_address,
        'venue_city', e.venue_city,
        'venue_country_code', e.venue_country_code,
        'venue_country_name', e.venue_country_name,
        'venue_name', e.venue_name,
        'venue_state', e.venue_state,
        'zip_code', e.venue_zip_code,

        'remaining_capacity',
            case
                when e.capacity is null then null
                else greatest(e.capacity - coalesce(ea.attendee_count, 0), 0)
            end
    )) as json_data
    from event e
    join "group" g using (group_id)
    join community c on c.community_id = g.community_id
    join group_category gc on g.group_category_id = gc.group_category_id
    left join meeting m_event on m_event.event_id = e.event_id
    left join (
        select event_id, count(*)::int as attendee_count
        from event_attendee
        group by event_id
    ) ea on ea.event_id = e.event_id
    where e.event_id = p_event_id
    and g.group_id = p_group_id
    and g.community_id = p_community_id;
$$ language sql;
