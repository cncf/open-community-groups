-- Returns the community's upcoming events.
-- Uses PL/pgSQL with `force_custom_plan` so each call is planned with the
-- actual community: a small community reads its own groups' upcoming events
-- instead of walking every upcoming event in the site.
create or replace function get_community_upcoming_events(p_community_id uuid, p_event_kind_ids text[])
returns json as $$
begin
    -- Summarize the next listed community events
    return (
        select coalesce(json_agg(
            get_event_summary(p_community_id, e.group_id, e.event_id)
            order by e.starts_at asc, e.event_id asc
        ), '[]')
        from (
            select e.event_id, e.group_id, e.starts_at
            from event e
            join "group" g using (group_id)
            where g.community_id = p_community_id
            and is_event_listed(e, g)
            and e.event_kind_id = any(p_event_kind_ids)
            and e.starts_at is not null
            and e.starts_at > now()
            order by e.starts_at asc, e.event_id asc
            limit 8
        ) e
    );
end;
$$ language plpgsql stable set plan_cache_mode = force_custom_plan;
