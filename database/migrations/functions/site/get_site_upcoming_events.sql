-- Returns the site's upcoming events.
create or replace function get_site_upcoming_events(p_event_kind_ids text[])
returns json as $$
    select coalesce(
        json_agg(
            get_event_summary(e.community_id, e.group_id, e.event_id)
            order by e.starts_at asc, e.event_id asc
        ),
        '[]'
    )
    from (
        select e.event_id, e.group_id, g.community_id, e.starts_at
        from event e
        join "group" g using (group_id)
        where g.active = true
        and e.published = true
        and e.event_kind_id = any(p_event_kind_ids)
        and e.starts_at is not null
        and e.starts_at > now()
        and e.canceled = false
        order by e.starts_at asc, e.event_id asc
        limit 8
    ) e;
$$ language sql;
