-- validate_update_event_dates validates update-specific event and session dates.
create or replace function validate_update_event_dates(
    p_event jsonb,
    p_event_before jsonb
)
returns void as $$
declare
    v_event_before_ends_at timestamptz := to_timestamp((p_event_before->>'ends_at')::bigint);
    v_event_before_starts_at timestamptz := to_timestamp((p_event_before->>'starts_at')::bigint);
    v_is_past_event boolean;
    v_new_ends_at timestamptz;
    v_new_starts_at timestamptz;
    v_session jsonb;
    v_session_ends_at timestamptz;
    v_session_starts_at timestamptz;
    v_timezone text := p_event->>'timezone';
begin
    -- Keep timestamp parsing aligned with update_event row updates
    if p_event->>'ends_at' is not null then
        v_new_ends_at := (p_event->>'ends_at')::timestamp at time zone v_timezone;
    end if;

    if p_event->>'starts_at' is not null then
        v_new_starts_at := (p_event->>'starts_at')::timestamp at time zone v_timezone;
    end if;

    -- Detect whether the current event snapshot is already in the past
    v_is_past_event := coalesce(
        v_event_before_ends_at,
        v_event_before_starts_at
    ) < current_timestamp;

    -- Prevent past events from being moved back into the future
    if v_is_past_event then
        if p_event->>'starts_at' is not null and v_new_starts_at > current_timestamp then
            raise exception 'event starts_at cannot be in the future';
        end if;

        if p_event->>'ends_at' is not null and v_new_ends_at > current_timestamp then
            raise exception 'event ends_at cannot be in the future';
        end if;

        if p_event->'sessions' is not null then
            for v_session in select jsonb_array_elements(p_event->'sessions')
            loop
                v_session_starts_at := (v_session->>'starts_at')::timestamp at time zone v_timezone;
                if v_session_starts_at > current_timestamp then
                    raise exception 'session starts_at cannot be in the future';
                end if;

                if v_session->>'ends_at' is not null then
                    v_session_ends_at := (v_session->>'ends_at')::timestamp at time zone v_timezone;
                    if v_session_ends_at > current_timestamp then
                        raise exception 'session ends_at cannot be in the future';
                    end if;
                end if;
            end loop;
        end if;
    end if;

    -- Prevent non-past events from moving into invalid past dates
    if not v_is_past_event then
        if p_event->>'starts_at' is not null and v_new_starts_at < current_timestamp then
            if v_event_before_starts_at >= current_timestamp then
                raise exception 'event starts_at cannot be in the past';
            elsif v_new_starts_at < v_event_before_starts_at then
                raise exception 'event starts_at cannot be earlier than current value';
            end if;
        end if;

        if p_event->>'ends_at' is not null and v_new_ends_at < current_timestamp then
            raise exception 'event ends_at cannot be in the past';
        end if;

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
    end if;
end;
$$ language plpgsql;
