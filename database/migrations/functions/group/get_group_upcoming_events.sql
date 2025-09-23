-- Returns upcoming events for a specific group.
create or replace function get_group_upcoming_events(
    p_community_id uuid,
    p_group_slug text,
    p_event_kind_ids text[],
    p_limit int
) returns json as $$
    select coalesce(json_agg(
        get_event_detailed(p_community_id, e.group_id, e.event_id)
    ), '[]')
    from (
        select e.event_id, e.group_id
        from event e
        join "group" g using (group_id)
        where g.community_id = p_community_id
        and g.slug = p_group_slug
        and g.active = true
        and e.published = true
        and e.event_kind_id = any(p_event_kind_ids)
        and e.starts_at is not null
        and e.starts_at > now()
        and e.canceled = false
        order by e.starts_at asc
        limit p_limit
    ) e;
$$ language sql;
