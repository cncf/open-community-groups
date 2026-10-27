-- Returns the surveys of a group event the organizer dashboard reads, with the
-- event row, narrowed to one survey when a survey id is given. A null survey id
-- returns every survey of the event, so single-survey readers must reject null
-- ids themselves. The event must belong to the group and not be deleted.
-- Organizer reads include canceled events and inactive groups, unlike
-- lock_event_for_surveys, which guards writes.
create or replace function group_dashboard_event_surveys(
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid default null
)
returns table (
    event_row event,
    event_survey_row event_survey
) as $$
    select
        e,
        s
    from event e
    join event_survey s on s.event_id = e.event_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and (p_event_survey_id is null or s.event_survey_id = p_event_survey_id);
$$ language sql stable;
