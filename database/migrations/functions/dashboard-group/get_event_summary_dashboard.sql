-- Returns the shared event summary extended with dashboard-only information.
create or replace function get_event_summary_dashboard(
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    select (
        get_event_summary(p_community_id, p_group_id, p_event_id)::jsonb
        || jsonb_strip_nulls(jsonb_build_object(
            'created_by_display_name', coalesce(u.name, u.username),
            'created_by_username', u.username
        ))::jsonb
    )::json
    from event e
    left join "user" u on u.user_id = e.created_by
    where e.event_id = p_event_id
    and e.group_id = p_group_id;
$$ language sql;
