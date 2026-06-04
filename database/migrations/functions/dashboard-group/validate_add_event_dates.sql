-- validate_add_event_dates validates add-specific event and session dates.
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
    -- New events cannot be created with past event dates
    if p_event->>'starts_at' is not null then
        v_starts_at := (p_event->>'starts_at')::timestamp at time zone v_timezone;
        if v_starts_at < current_timestamp then
            raise exception 'event starts_at cannot be in the past';
        end if;
    end if;

    if p_event->>'ends_at' is not null then
        v_ends_at := (p_event->>'ends_at')::timestamp at time zone v_timezone;
        if v_ends_at < current_timestamp then
            raise exception 'event ends_at cannot be in the past';
        end if;
    end if;

    -- New event sessions cannot be created with past session dates
    if p_event->'sessions' is not null then
        for v_session in select jsonb_array_elements(p_event->'sessions')
        loop
            v_session_starts_at := (v_session->>'starts_at')::timestamp at time zone v_timezone;
            if v_session_starts_at < current_timestamp then
                raise exception 'session starts_at cannot be in the past';
            end if;

            if v_session->>'ends_at' is not null then
                v_session_ends_at := (v_session->>'ends_at')::timestamp at time zone v_timezone;
                if v_session_ends_at < current_timestamp then
                    raise exception 'session ends_at cannot be in the past';
                end if;
            end if;
        end loop;
    end if;
end;
$$ language plpgsql;
