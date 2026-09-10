-- Determines the meeting sync state of a session after an event update. The
-- prior state is the stored session row, its speaker rows and the locked
-- parent event row with its host rows; the new state is the session and event
-- payloads. Returns null when no meeting is involved, false when the provider
-- meeting needs create, update or delete work, and true when the provider
-- meeting already matches the payload. Prior timestamps are compared at the
-- whole-second precision the payload carries.
create or replace function is_session_meeting_in_sync(
    p_before_session session,
    p_after_session jsonb,
    p_before_event event,
    p_after_event jsonb
)
returns boolean as $$
declare
    v_after_ends_at timestamptz;
    v_after_event_host_ids uuid[];
    v_after_event_meeting_recording_requested boolean := coalesce((p_after_event->>'meeting_recording_requested')::boolean, true);
    v_after_meeting_hosts text[] := jsonb_text_array(p_after_session->'meeting_hosts');
    v_after_meeting_provider_id text := p_after_session->>'meeting_provider_id';
    v_after_meeting_requested boolean := (p_after_session->>'meeting_requested')::boolean;
    v_after_name text := p_after_session->>'name';
    v_after_session_kind_id text := p_after_session->>'kind';
    v_after_speaker_ids uuid[];
    v_after_starts_at timestamptz;
    v_after_timezone text := p_after_event->>'timezone';

    v_before_ends_at timestamptz := date_trunc('second', p_before_session.ends_at);
    v_before_event_host_ids uuid[];
    v_before_meeting_requested boolean := coalesce(p_before_session.meeting_requested, false);
    v_before_speaker_ids uuid[];
    v_before_starts_at timestamptz := date_trunc('second', p_before_session.starts_at);
begin
    -- Parse the payload schedule in the payload event timezone
    v_after_starts_at := (p_after_session->>'starts_at')::timestamp at time zone v_after_timezone;
    v_after_ends_at := (p_after_session->>'ends_at')::timestamp at time zone v_after_timezone;

    -- Load the prior event host and session speaker rows
    select array_agg(eh.user_id order by eh.user_id)
    into v_before_event_host_ids
    from event_host eh
    where eh.event_id = p_before_event.event_id;

    select array_agg(ss.user_id order by ss.user_id)
    into v_before_speaker_ids
    from session_speaker ss
    where ss.session_id = p_before_session.session_id;

    -- Collect the payload event hosts (uuid strings) and session speakers (objects with user_id)
    select array_agg(h order by h)
    into v_after_event_host_ids
    from (select h::uuid as h from jsonb_array_elements_text(p_after_event->'hosts') h) sub;

    select array_agg(s order by s)
    into v_after_speaker_ids
    from (select (s->>'user_id')::uuid as s from jsonb_array_elements(p_after_session->'speakers') s) sub;

    -- Schedule deletion work when a requested meeting is no longer requested
    if v_after_meeting_requested is distinct from true then
        return case when v_before_meeting_requested = true then false else null end;
    end if;

    -- Schedule deletion work when a session with a meeting becomes in-person
    if v_after_session_kind_id = 'in-person' and v_before_meeting_requested = true then
        return false;
    end if;

    -- Preserve real pending/error states instead of hiding unsynced work
    if v_before_meeting_requested = true and p_before_session.meeting_in_sync = false then
        return false;
    end if;

    -- Provider create/update sync is not claimed after the session starts
    if v_before_meeting_requested = true
       and p_before_session.meeting_in_sync = true
       and v_before_starts_at <= current_timestamp then
        return true;
    end if;

    -- Report whether every provider-visible field is unchanged
    return v_before_meeting_requested = true
        and v_before_ends_at is not distinct from v_after_ends_at
        and v_before_event_host_ids is not distinct from v_after_event_host_ids
        and coalesce(p_before_event.meeting_recording_requested, true) = v_after_event_meeting_recording_requested
        and p_before_session.meeting_hosts is not distinct from v_after_meeting_hosts
        and p_before_session.meeting_provider_id is not distinct from v_after_meeting_provider_id
        and p_before_session.name = v_after_name
        and v_before_speaker_ids is not distinct from v_after_speaker_ids
        and v_before_starts_at is not distinct from v_after_starts_at
        and p_before_event.timezone = v_after_timezone;
end;
$$ language plpgsql;
