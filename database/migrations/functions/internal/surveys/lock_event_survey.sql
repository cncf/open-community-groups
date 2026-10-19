-- Locks a survey of an event and returns its row. Callers lock the parent
-- event first, so survey locks always follow the event lock order.
create or replace function lock_event_survey(
    p_event_id uuid,
    p_event_survey_id uuid
)
returns event_survey as $$
declare
    v_event_survey event_survey;
begin
    -- Lock the survey when it belongs to the event
    select s.*
    into v_event_survey
    from event_survey s
    where s.event_survey_id = p_event_survey_id
    and s.event_id = p_event_id
    for update of s;

    -- Reject missing surveys and surveys of another event
    if not found then
        raise exception 'event survey not found' using errcode = 'OCG01';
    end if;

    -- Return the locked survey row
    return v_event_survey;
end;
$$ language plpgsql;
