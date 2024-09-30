-- Returns the community events that match the filters provided.
create or replace function search_community_events(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'address', address,
        'cancelled', cancelled,
        'city', city,
        'country', country,
        'description', description,
        'ends_at', floor(extract(epoch from ends_at)),
        'event_kind_id', event_kind_id,
        'icon_url', icon_url,
        'postponed', postponed,
        'slug', event_slug,
        'starts_at', floor(extract(epoch from starts_at)),
        'state', state,
        'title', title,
        'venue', venue,
        'group_name', group_name,
        'group_slug', group_slug
    )), '[]') as json_data
    from (
        select
            e.address,
            e.cancelled,
            e.city,
            e.country,
            e.description,
            e.ends_at,
            e.event_kind_id,
            e.icon_url,
            e.postponed,
            e.slug as event_slug,
            e.starts_at,
            e.state,
            e.title,
            e.venue,
            g.name as group_name,
            g.slug as group_slug
        from event e
        join "group" g using (group_id)
        where g.community_id = $1
        and e.starts_at > now()
        order by e.starts_at asc
    ) events;
$$ language sql;
