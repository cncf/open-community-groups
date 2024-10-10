-- Returns the community's upcoming events.
create or replace function get_community_upcoming_in_person_events(p_community_id uuid, p_event_kind_id text)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'city', city,
        'icon_url', icon_url,
        'slug', event_slug,
        'starts_at', floor(extract(epoch from starts_at)),
        'state', state,
        'title', title,
        'group_name', group_name,
        'group_slug', group_slug
    )), '[]')
    from (
        select
            e.city,
            e.icon_url,
            e.slug as event_slug,
            e.starts_at,
            e.state,
            e.title,
            g.name as group_name,
            g.slug as group_slug
        from event e
        join "group" g using (group_id)
        where g.community_id = p_community_id
        and e.event_kind_id = p_event_kind_id
        and e.icon_url is not null
        and e.starts_at > now()
        and e.cancelled = false
        and e.postponed = false
        order by e.starts_at asc
        limit 9
    ) events;
$$ language sql;
