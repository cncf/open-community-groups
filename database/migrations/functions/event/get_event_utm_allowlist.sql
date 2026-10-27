-- get_event_utm_allowlist returns the UTM values accepted for the views of an
-- event: its group campaigns and sources, and the default mediums together
-- with its group extra mediums. Returns null when the event is not published.
create or replace function get_event_utm_allowlist(p_event_id uuid)
returns json as $$
    select json_build_object(
        'campaigns', g.utm_campaigns,
        'mediums', array(
            select um.utm_medium_id
            from utm_medium um
            union
            select unnest(g.utm_mediums)
            order by 1
        ),
        'sources', g.utm_sources
    )
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and e.deleted = false
    and e.published = true;
$$ language sql stable;
