-- Validates that a survey can be ready: it needs at least one question, and a
-- configured closing date must be in the future and after the effective
-- opening time. Callers pass the locked survey row with the settings being
-- applied and the locked event row.
create or replace function validate_event_survey_schedule(
    p_event_survey event_survey,
    p_event event
)
returns void as $$
declare
    v_effective_opens_at timestamptz := event_survey_effective_opens_at(p_event_survey, p_event);
begin
    -- Require at least one question
    if jsonb_array_length(p_event_survey.questions) = 0 then
        raise exception 'event survey must have at least one question' using errcode = 'OCG01';
    end if;

    -- Require a configured closing date in the future
    if p_event_survey.closes_at <= current_timestamp then
        raise exception 'event survey closing date must be in the future' using errcode = 'OCG01';
    end if;

    -- Require a configured closing date after the effective opening time
    if p_event_survey.closes_at <= v_effective_opens_at then
        raise exception 'event survey closing date must be after the survey opens' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;
