-- Validates the event, registration and session dates of an update payload
-- against the locked prior event row and its stored sessions. Past events
-- cannot move into the future, live events cannot move earlier than their
-- current schedule, and future events cannot move into the past. Prior
-- timestamps are compared at the whole-second precision the payload carries.
create or replace function validate_update_event_dates(
    p_event jsonb,
    p_before event
)
returns void as $$
declare
    v_before_ends_at timestamptz := date_trunc('second', p_before.ends_at);
    v_before_starts_at timestamptz := date_trunc('second', p_before.starts_at);
    v_is_past_event boolean;
    v_new_ends_at timestamptz;
    v_new_starts_at timestamptz;
    v_registration_ends_at timestamptz;
    v_registration_starts_at timestamptz;
    v_session jsonb;
    v_session_before_ends_at timestamptz;
    v_session_before_starts_at timestamptz;
    v_session_ends_at timestamptz;
    v_session_starts_at timestamptz;
    v_timezone text := p_event->>'timezone';
begin
    -- Parse the submitted schedule in the payload timezone
    v_new_ends_at := (p_event->>'ends_at')::timestamp at time zone v_timezone;
    v_new_starts_at := (p_event->>'starts_at')::timestamp at time zone v_timezone;
    v_registration_ends_at := (p_event->>'registration_ends_at')::timestamp at time zone v_timezone;
    v_registration_starts_at := (p_event->>'registration_starts_at')::timestamp at time zone v_timezone;

    -- Published events must keep the start date required by publish_event
    if p_before.published = true and v_new_starts_at is null then
        raise exception 'published event must have a start date' using errcode = 'OCG01';
    end if;

    -- Require configured registration openings to leave time before close
    if v_registration_starts_at is not null
       and v_registration_ends_at is not null
       and v_registration_starts_at >= v_registration_ends_at then
        raise exception 'registration starts_at must be before registration ends_at' using errcode = 'OCG01';
    end if;

    -- Keep configured registration openings from extending past the event start
    if v_registration_starts_at is not null
       and v_new_starts_at is not null
       and v_registration_starts_at > v_new_starts_at then
        raise exception 'registration starts_at cannot be after event starts_at' using errcode = 'OCG01';
    end if;

    -- Keep configured registration closes from extending past the event start
    if v_registration_ends_at is not null
       and v_new_starts_at is not null
       and v_registration_ends_at > v_new_starts_at then
        raise exception 'registration ends_at cannot be after event starts_at' using errcode = 'OCG01';
    end if;

    -- Detect whether the current event is already over, treating dateless events as non-past
    v_is_past_event := coalesce(coalesce(v_before_ends_at, v_before_starts_at) < current_timestamp, false);

    -- Keep past events in the past
    if v_is_past_event then
        -- Reject a start moved into the future
        if v_new_starts_at > current_timestamp then
            raise exception 'event starts_at cannot be in the future' using errcode = 'OCG01';
        end if;

        -- Reject an end moved into the future
        if v_new_ends_at > current_timestamp then
            raise exception 'event ends_at cannot be in the future' using errcode = 'OCG01';
        end if;

        -- Reject sessions moved into the future
        for v_session in select jsonb_array_elements(p_event->'sessions')
        loop
            v_session_ends_at := (v_session->>'ends_at')::timestamp at time zone v_timezone;
            v_session_starts_at := (v_session->>'starts_at')::timestamp at time zone v_timezone;

            -- Reject a session start in the future
            if v_session_starts_at > current_timestamp then
                raise exception 'session starts_at cannot be in the future' using errcode = 'OCG01';
            end if;

            -- Reject a session end in the future
            if v_session_ends_at > current_timestamp then
                raise exception 'session ends_at cannot be in the future' using errcode = 'OCG01';
            end if;
        end loop;

        return;
    end if;

    -- Reject a start moved into the past unless a live event keeps or delays its current start
    if v_new_starts_at < current_timestamp then
        -- Reject future or dateless events moving into the past
        if v_before_starts_at is null or v_before_starts_at >= current_timestamp then
            raise exception 'event starts_at cannot be in the past' using errcode = 'OCG01';
        -- Reject live events moving earlier than their current start
        elsif v_new_starts_at < v_before_starts_at then
            raise exception 'event starts_at cannot be earlier than current value' using errcode = 'OCG01';
        end if;
    end if;

    -- Reject an end moved into the past
    if v_new_ends_at < current_timestamp then
        raise exception 'event ends_at cannot be in the past' using errcode = 'OCG01';
    end if;

    -- Apply the same rules to each submitted session against its stored row
    for v_session in select jsonb_array_elements(p_event->'sessions')
    loop
        v_session_before_ends_at := null;
        v_session_before_starts_at := null;
        v_session_ends_at := (v_session->>'ends_at')::timestamp at time zone v_timezone;
        v_session_starts_at := (v_session->>'starts_at')::timestamp at time zone v_timezone;

        -- Load the stored schedule of an existing session
        if v_session->>'session_id' is not null then
            select date_trunc('second', s.ends_at), date_trunc('second', s.starts_at)
            into v_session_before_ends_at, v_session_before_starts_at
            from session s
            where s.session_id = (v_session->>'session_id')::uuid
            and s.event_id = p_before.event_id;
        end if;

        -- Reject a session start moved into the past unless a live session keeps or delays it
        if v_session_starts_at < current_timestamp then
            -- Reject new or future sessions moving into the past
            if v_session_before_starts_at is null or v_session_before_starts_at >= current_timestamp then
                raise exception 'session starts_at cannot be in the past' using errcode = 'OCG01';
            -- Reject live sessions moving earlier than their current start
            elsif v_session_starts_at < v_session_before_starts_at then
                raise exception 'session starts_at cannot be earlier than current value' using errcode = 'OCG01';
            end if;
        end if;

        -- Reject a session end moved into the past unless a finished session keeps or delays it
        if v_session_ends_at < current_timestamp then
            -- Reject new or unfinished sessions ending in the past
            if v_session_before_ends_at is null or v_session_before_ends_at >= current_timestamp then
                raise exception 'session ends_at cannot be in the past' using errcode = 'OCG01';
            -- Reject finished sessions moving earlier than their current end
            elsif v_session_ends_at < v_session_before_ends_at then
                raise exception 'session ends_at cannot be earlier than current value' using errcode = 'OCG01';
            end if;
        end if;
    end loop;
end;
$$ language plpgsql;
