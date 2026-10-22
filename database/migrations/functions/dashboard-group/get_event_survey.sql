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
        event_survey_summary_json(s, e) || jsonb_build_object(
            'created_at', epoch_seconds(s.created_at),
            'questions', s.questions,

            'closed_at', epoch_seconds(s.closed_at),
            'description', s.description,
            'opens_at', epoch_seconds(s.opens_at),
            'updated_at', epoch_seconds(s.updated_at)
        )
    )::json
    from event e
    join event_survey s on s.event_id = e.event_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and s.event_survey_id = p_event_survey_id;
$$ language sql stable;
