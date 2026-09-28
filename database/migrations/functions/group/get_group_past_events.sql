-- Returns past events for a specific group.
create or replace function get_group_past_events(
    p_community_id uuid,
    p_group_slug text,
    p_event_kind_ids text[],
    p_limit int
) returns json as $$
    select coalesce(json_agg(
        get_event_summary(e.community_id, e.group_id, e.event_id)
        order by e.starts_at desc, e.event_id asc
    ), '[]')
    from (
        select
            page_events.community_id,
            page_events.event_id,
            page_events.group_id,
            page_events.starts_at
        from list_group_page_events(
            p_community_id,
            p_group_slug,
            p_event_kind_ids
        ) page_events
        where page_events.starts_at <= now()
        order by page_events.starts_at desc, page_events.event_id asc
        limit p_limit
    ) e;
$$ language sql;
