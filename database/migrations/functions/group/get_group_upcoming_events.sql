-- Returns upcoming events for a specific group.
-- Uses PL/pgSQL with `force_generic_plan` so each connection caches its plan
-- instead of planning the SQL-language body on every call.
create or replace function get_group_upcoming_events(
    p_community_id uuid,
    p_group_slug text,
    p_event_kind_ids text[],
    p_limit int
) returns json as $$
begin
    -- Summarize the next upcoming page events
    return (
        select coalesce(json_agg(
            get_event_summary(e.community_id, e.group_id, e.event_id)
            order by e.starts_at asc, e.event_id asc
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
            where page_events.starts_at > now()
            order by page_events.starts_at asc, page_events.event_id asc
            limit p_limit
        ) e
    );
end;
$$ language plpgsql stable set plan_cache_mode = force_generic_plan;
