-- is_session_meeting_in_sync determines meeting sync status for sessions.
create or replace function is_session_meeting_in_sync(
    p_before_session jsonb,
    p_after_session jsonb,
    p_before_event jsonb,
    p_after_event jsonb
)
returns boolean as $$
declare
    v_after_ends_at timestamptz;
    v_after_event_host_ids uuid[];
    v_after_meeting_hosts text[] := case when p_after_session->'meeting_hosts' is not null then array(select jsonb_array_elements_text(p_after_session->'meeting_hosts')) else null end;
    v_after_meeting_provider_id text := p_after_session->>'meeting_provider_id';
    v_after_meeting_requested boolean := (p_after_session->>'meeting_requested')::boolean;
    v_after_name text := p_after_session->>'name';
    v_after_session_kind_id text := p_after_session->>'kind';
    v_after_speaker_ids uuid[];
    v_after_starts_at timestamptz;
    v_after_timezone text := p_after_event->>'timezone';

    v_before_ends_at timestamptz := to_timestamp((p_before_session->>'ends_at')::double precision);
    v_before_event_host_ids uuid[];
    v_before_meeting_hosts text[] := case when p_before_session->'meeting_hosts' is not null then array(select jsonb_array_elements_text(p_before_session->'meeting_hosts')) else null end;
    v_before_meeting_provider_id text := p_before_session->>'meeting_provider_id';
    v_before_meeting_requested boolean := coalesce((p_before_session->>'meeting_requested')::boolean, false);
    v_before_name text := p_before_session->>'name';
    v_before_speaker_ids uuid[];
    v_before_starts_at timestamptz := to_timestamp((p_before_session->>'starts_at')::double precision);
    v_before_timezone text := p_before_event->>'timezone';

    v_in_sync boolean;
begin
    -- Calculate time fields
    v_after_starts_at := (p_after_session->>'starts_at')::timestamp at time zone v_after_timezone;
    v_after_ends_at := (p_after_session->>'ends_at')::timestamp at time zone v_after_timezone;

    -- Extract event host user_ids from before event (array of user objects with user_id)
    select array_agg(h order by h)
    into v_before_event_host_ids
    from (select (h->>'user_id')::uuid as h from jsonb_array_elements(p_before_event->'hosts') h) sub;

    -- Extract event host user_ids from after event (array of uuid strings)
    select array_agg(h order by h)
    into v_after_event_host_ids
    from (select h::uuid as h from jsonb_array_elements_text(p_after_event->'hosts') h) sub;

    -- Extract session speaker user_ids from before session (array of speaker objects)
    select array_agg(s order by s)
    into v_before_speaker_ids
    from (select (s->>'user_id')::uuid as s from jsonb_array_elements(p_before_session->'speakers') s) sub;

    -- Extract session speaker user_ids from after session (array of speaker objects)
    select array_agg(s order by s)
    into v_after_speaker_ids
    from (select (s->>'user_id')::uuid as s from jsonb_array_elements(p_after_session->'speakers') s) sub;

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
        and v_before_ends_at is not distinct from v_after_ends_at
        and v_before_event_host_ids is not distinct from v_after_event_host_ids
        and v_before_meeting_hosts is not distinct from v_after_meeting_hosts
        and v_before_meeting_provider_id is not distinct from v_after_meeting_provider_id
        and v_before_name = v_after_name
        and v_before_speaker_ids is not distinct from v_after_speaker_ids
        and v_before_starts_at is not distinct from v_after_starts_at
        and v_before_timezone = v_after_timezone;

    return v_in_sync;
end;
$$ language plpgsql;
