-- Returns a survey of a group event: its summary plus the description, the
-- questions and the dates the editor needs. Null when the survey does not
-- belong to the group event.
create or replace function get_event_survey(
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid
)
returns json as $$
    select (
        event_survey_summary_json(gs.event_survey_row, gs.event_row) || jsonb_build_object(
            'created_at', epoch_seconds((gs.event_survey_row).created_at),
            'questions', (gs.event_survey_row).questions,

            'closed_at', epoch_seconds((gs.event_survey_row).closed_at),
            'description', (gs.event_survey_row).description,
            'opens_at', epoch_seconds((gs.event_survey_row).opens_at),
            'updated_at', epoch_seconds((gs.event_survey_row).updated_at)
        )
    )::json
    from group_dashboard_event_surveys(p_group_id, p_event_id, p_event_survey_id) gs
    where p_event_survey_id is not null;
$$ language sql stable;
