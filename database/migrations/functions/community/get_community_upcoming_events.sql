-- Returns the community's upcoming events.
create or replace function get_community_upcoming_events(p_community_id uuid, p_event_kind_ids text[])
returns json as $$
    select coalesce(json_agg(
        get_event_summary(p_community_id, e.group_id, e.event_id)
    ), '[]')
    from (
        select e.event_id, e.group_id
        from event e
        join "group" g using (group_id)
        where g.community_id = p_community_id
        and g.active = true
        and e.published = true
        and e.event_kind_id = any(p_event_kind_ids)
        and (g.city is not null or e.venue_city is not null)
        and e.starts_at is not null
        and e.starts_at > now()
        and e.canceled = false
        and e.logo_url is not null
        order by e.starts_at asc
        limit 8
    ) e;
$$ language sql;
