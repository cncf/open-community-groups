-- Returns the surveys of a group event as summary rows ordered by creation.
create or replace function list_event_surveys(
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    select coalesce(
        json_agg(
            event_survey_summary_json(s, e)
            order by s.created_at, s.event_survey_id
        ),
        '[]'::json
    )
    from event e
    join event_survey s on s.event_id = e.event_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false;
$$ language sql stable;
