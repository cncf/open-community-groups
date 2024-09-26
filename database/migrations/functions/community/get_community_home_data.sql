-- Returns the information needed to render the community home page.
create or replace function get_community_home_data(p_community_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'community', (select get_community_data(p_community_id)),
        'recently_added_groups', (
            select coalesce(json_agg(json_build_object(
                'city', city,
                'country', country,
                'icon_url', icon_url,
                'name', name,
                'region_name', region_name,
                'slug', slug,
                'state', state
            )), '[]')
            from (
                select
                    g.city,
                    g.country,
                    g.icon_url,
                    g.name,
                    r.name as region_name,
                    g.slug,
                    g.state
                from "group" g
                join region r using (region_id)
                where g.community_id = $1
                order by g.created_at desc
                limit 9
            ) groups
        ),
        'upcoming_in_person_events', (
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
                where g.community_id = $1
                and e.icon_url is not null
                and e.starts_at > now()
                and e.cancelled = false
                and e.postponed = false
                and e.event_kind_id = 'in-person'
                order by e.starts_at asc
                limit 9
            ) events
        ),
        'upcoming_online_events', (
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
                where g.community_id = $1
                and e.icon_url is not null
                and e.starts_at > now()
                and e.cancelled = false
                and e.postponed = false
                and e.event_kind_id = 'virtual'
                order by e.starts_at asc
                limit 9
            ) events
        )
    )) as json_data
    from community
    where community_id = p_community_id;
$$ language sql;
