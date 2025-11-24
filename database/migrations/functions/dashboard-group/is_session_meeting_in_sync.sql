-- is_session_meeting_in_sync determines meeting sync status for sessions.
create or replace function is_session_meeting_in_sync(
    p_before_session jsonb,
    p_after_session jsonb,
    p_before_timezone text,
    p_after_timezone text
)
returns boolean as $$
declare
    v_before_name text := p_before_session->>'name';
    v_before_starts_at timestamptz := to_timestamp((p_before_session->>'starts_at')::double precision);
    v_before_ends_at timestamptz := to_timestamp((p_before_session->>'ends_at')::double precision);
    v_before_meeting_requested boolean := coalesce((p_before_session->>'meeting_requested')::boolean, false);
    v_before_meeting_requires_password boolean := coalesce((p_before_session->>'meeting_requires_password')::boolean, false);

    v_after_name text := p_after_session->>'name';
    v_after_starts_at timestamptz := (p_after_session->>'starts_at')::timestamp at time zone p_after_timezone;
    v_after_ends_at timestamptz := (p_after_session->>'ends_at')::timestamp at time zone p_after_timezone;
    v_after_meeting_requested boolean := (p_after_session->>'meeting_requested')::boolean;
    v_after_meeting_requires_password boolean := coalesce((p_after_session->>'meeting_requires_password')::boolean, false);
    v_after_session_kind_id text := p_after_session->>'kind';

    v_in_sync boolean;
begin
    -- If meeting is not requested in the new state, check if it was previously
    -- requested to determine if we need to trigger deletion
    if v_after_meeting_requested is distinct from true then
        return case when v_before_meeting_requested = true then false else null end;
    end if;

    -- If kind changed to 'in-person' and meeting was previously requested,
    -- trigger deletion
    if v_after_session_kind_id = 'in-person' and v_before_meeting_requested = true then
        return false;
    end if;

    -- Determine if all relevant fields remain in sync
    v_in_sync := v_before_meeting_requested = true
        and v_before_name = v_after_name
        and v_before_starts_at is not distinct from v_after_starts_at
        and v_before_ends_at is not distinct from v_after_ends_at
        and p_before_timezone = p_after_timezone
        and v_before_meeting_requires_password is not distinct from v_after_meeting_requires_password;

    return v_in_sync;
end;
$$ language plpgsql;
