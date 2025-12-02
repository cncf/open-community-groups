-- is_event_meeting_in_sync determines meeting sync status for events.
create or replace function is_event_meeting_in_sync(
    p_before_event jsonb,
    p_after_event jsonb
)
returns boolean as $$
declare
    v_before_name text := p_before_event->>'name';
    v_before_starts_at timestamptz := to_timestamp((p_before_event->>'starts_at')::double precision);
    v_before_ends_at timestamptz := to_timestamp((p_before_event->>'ends_at')::double precision);
    v_before_timezone text := p_before_event->>'timezone';
    v_before_meeting_provider_id text := p_before_event->>'meeting_provider_id';
    v_before_meeting_requested boolean := coalesce((p_before_event->>'meeting_requested')::boolean, false);
    v_before_meeting_requires_password boolean := coalesce((p_before_event->>'meeting_requires_password')::boolean, false);

    v_after_name text := p_after_event->>'name';
    v_after_timezone text := p_after_event->>'timezone';
    v_after_starts_at timestamptz := (p_after_event->>'starts_at')::timestamp at time zone v_after_timezone;
    v_after_ends_at timestamptz := (p_after_event->>'ends_at')::timestamp at time zone v_after_timezone;
    v_after_meeting_provider_id text := p_after_event->>'meeting_provider_id';
    v_after_meeting_requested boolean := (p_after_event->>'meeting_requested')::boolean;
    v_after_meeting_requires_password boolean := coalesce((p_after_event->>'meeting_requires_password')::boolean, false);

    v_in_sync boolean;
begin
    -- If meeting is not requested in the new state, check if it was previously
    -- requested to determine if we need to trigger deletion
    if v_after_meeting_requested is distinct from true then
        return case when v_before_meeting_requested = true then false else null end;
    end if;

    -- Determine if all relevant fields remain in sync
    v_in_sync := v_before_meeting_requested = true
        and v_before_name = v_after_name
        and v_before_starts_at is not distinct from v_after_starts_at
        and v_before_ends_at is not distinct from v_after_ends_at
        and v_before_timezone = v_after_timezone
        and v_before_meeting_provider_id is not distinct from v_after_meeting_provider_id
        and v_before_meeting_requires_password is not distinct from v_after_meeting_requires_password;

    return v_in_sync;
end;
$$ language plpgsql;
