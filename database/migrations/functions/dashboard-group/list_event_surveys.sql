-- Returns the surveys of a group event as summary rows ordered by creation.
create or replace function list_event_surveys(
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    select coalesce(
        json_agg(
            event_survey_summary_json(gs.event_survey_row, gs.event_row)
            order by (gs.event_survey_row).created_at, (gs.event_survey_row).event_survey_id
        ),
        '[]'::json
    )
    from group_dashboard_event_surveys(p_group_id, p_event_id) gs;
$$ language sql stable;
