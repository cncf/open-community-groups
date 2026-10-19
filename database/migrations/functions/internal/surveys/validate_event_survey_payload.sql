-- Validates a survey configuration payload against its event and returns the
-- resolved survey settings. The survey revision is passed to callers
-- separately and is not part of the payload.
--
-- Payload contract (the dashboard EventSurveyInput):
--   anonymous    boolean, required
--   audience     'checked-in' or 'confirmed', required
--   closes_at    local event time ('YYYY-MM-DDTHH:MM:SS'), optional
--   description  plain text up to 500 characters, optional; blank means none
--   opens_at     local event time ('YYYY-MM-DDTHH:MM:SS'), optional
--   questions    questionnaire questions array, up to 30, required
--   title        non-blank text up to 120 characters, required
--
-- The limits match MAX_LEN_DESCRIPTION_SHORT, MAX_EVENT_SURVEY_QUESTIONS and
-- MAX_LEN_ENTITY_NAME in Rust. Dates are interpreted in the event timezone,
-- and the closing date must be after the opening date when both are set.
create or replace function validate_event_survey_payload(
    p_event event,
    p_payload jsonb
)
returns table (
    anonymous boolean,
    audience text,
    closes_at timestamptz,
    description text,
    opens_at timestamptz,
    questions jsonb,
    title text
) as $$
declare
    v_closes_at timestamptz;
    v_opens_at timestamptz;
begin
    -- Require an object payload
    if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
        raise exception 'event survey payload must be an object' using errcode = 'OCG01';
    end if;

    -- Require a boolean anonymous flag
    if jsonb_typeof(p_payload->'anonymous') is distinct from 'boolean' then
        raise exception 'event survey anonymous flag must be a boolean' using errcode = 'OCG01';
    end if;

    -- Require a supported audience
    if jsonb_typeof(p_payload->'audience') is distinct from 'string'
        or p_payload->>'audience' not in ('checked-in', 'confirmed')
    then
        raise exception 'event survey audience is invalid' using errcode = 'OCG01';
    end if;

    -- Parse the optional dates in the event timezone
    begin
        v_closes_at := (p_payload->>'closes_at')::timestamp at time zone p_event.timezone;
        v_opens_at := (p_payload->>'opens_at')::timestamp at time zone p_event.timezone;
    exception
        -- Reject values that are not local date times
        when datetime_field_overflow or invalid_datetime_format then
            raise exception 'event survey dates are invalid' using errcode = 'OCG01';
    end;

    -- Require the closing date to follow the opening date
    if v_closes_at <= v_opens_at then
        raise exception 'event survey closing date must be after the opening date' using errcode = 'OCG01';
    end if;

    -- Require descriptions to be strings when present
    if jsonb_typeof(p_payload->'description') not in ('null', 'string') then
        raise exception 'event survey description must be a string' using errcode = 'OCG01';
    end if;

    -- Reject descriptions longer than the short description limit
    if char_length(btrim(p_payload->>'description')) > 500 then
        raise exception 'event survey description is too long' using errcode = 'OCG01';
    end if;

    -- Validate the question definitions
    perform validate_questionnaire_questions_payload(p_payload->'questions');

    -- Enforce the per-survey question limit
    if jsonb_array_length(p_payload->'questions') > 30 then
        raise exception 'surveys can have up to 30 questions' using errcode = 'OCG01';
    end if;

    -- Require a non-blank string title
    if jsonb_typeof(p_payload->'title') is distinct from 'string'
        or nullif(btrim(p_payload->>'title'), '') is null
    then
        raise exception 'event survey title is required' using errcode = 'OCG01';
    end if;

    -- Reject titles longer than the entity name limit
    if char_length(btrim(p_payload->>'title')) > 120 then
        raise exception 'event survey title is too long' using errcode = 'OCG01';
    end if;

    -- Return the normalized survey settings
    return query
    select
        (p_payload->>'anonymous')::boolean,
        p_payload->>'audience',
        v_closes_at,
        nullif(btrim(p_payload->>'description'), ''),
        v_opens_at,
        p_payload->'questions',
        btrim(p_payload->>'title');
end;
$$ language plpgsql;
