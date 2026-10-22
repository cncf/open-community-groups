-- Validates the event, registration and session dates of an add payload.
create or replace function validate_add_event_dates(p_event jsonb)
returns void as $$
declare
    v_ends_at timestamptz;
    v_session jsonb;
    v_session_ends_at timestamptz;
    v_session_starts_at timestamptz;
    v_starts_at timestamptz;
    v_timezone text := p_event->>'timezone';
begin
    -- Parse the submitted event schedule in the payload timezone
    v_ends_at := (p_event->>'ends_at')::timestamp at time zone v_timezone;
    v_starts_at := (p_event->>'starts_at')::timestamp at time zone v_timezone;

    -- Reject new events starting in the past
    if v_starts_at < current_timestamp then
        raise exception 'event starts_at cannot be in the past' using errcode = 'OCG01';
    end if;

    -- Reject new events ending in the past
    if v_ends_at < current_timestamp then
        raise exception 'event ends_at cannot be in the past' using errcode = 'OCG01';
    end if;

    -- Validate the configured registration window against the event start
    perform validate_event_registration_window(
        (p_event->>'registration_starts_at')::timestamp at time zone v_timezone,
        (p_event->>'registration_ends_at')::timestamp at time zone v_timezone,
        v_starts_at
    );

    -- Reject new sessions scheduled in the past
    for v_session in select jsonb_array_elements(p_event->'sessions')
    loop
        -- Parse the submitted session schedule in the payload timezone
        v_session_ends_at := (v_session->>'ends_at')::timestamp at time zone v_timezone;
        v_session_starts_at := (v_session->>'starts_at')::timestamp at time zone v_timezone;

        -- Reject a session starting in the past
        if v_session_starts_at < current_timestamp then
            raise exception 'session starts_at cannot be in the past' using errcode = 'OCG01';
        end if;

        -- Reject a session ending in the past
        if v_session_ends_at < current_timestamp then
            raise exception 'session ends_at cannot be in the past' using errcode = 'OCG01';
        end if;
    end loop;
end;
$$ language plpgsql;
