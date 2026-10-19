-- Returns when a survey opens: the later of its custom opening time and the
-- event's effective end. Null when the event has no dates, because a survey
-- never opens before its event ends.
create or replace function event_survey_effective_opens_at(
    p_event_survey event_survey,
    p_event event
)
returns timestamptz as $$
    select case
        when event_effective_ends_at(p_event) is null then null
        else greatest(p_event_survey.opens_at, event_effective_ends_at(p_event))
    end;
$$ language sql immutable;
