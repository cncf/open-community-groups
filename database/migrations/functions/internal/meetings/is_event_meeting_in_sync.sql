-- Determines the meeting sync state of an event after an update. The prior
-- state is the locked event row plus its host and speaker rows; the new state
-- is the update payload. Returns null when no meeting is involved, false when
-- the provider meeting needs create, update or delete work, and true when the
-- provider meeting already matches the payload. Prior timestamps are compared
-- at the whole-second precision the payload carries.
create or replace function is_event_meeting_in_sync(
    p_before event,
    p_after jsonb
)
returns boolean as $$
declare
    v_after_ends_at timestamptz;
    v_after_host_ids uuid[];
    v_after_meeting_hosts text[] := jsonb_text_array(p_after->'meeting_hosts');
    v_after_meeting_provider_id text := p_after->>'meeting_provider_id';
    v_after_meeting_recording_requested boolean := coalesce((p_after->>'meeting_recording_requested')::boolean, true);
    v_after_meeting_requested boolean := (p_after->>'meeting_requested')::boolean;
    v_after_name text := p_after->>'name';
    v_after_speaker_ids uuid[];
    v_after_starts_at timestamptz;
    v_after_timezone text := p_after->>'timezone';

    v_before_ends_at timestamptz := date_trunc('second', p_before.ends_at);
    v_before_host_ids uuid[];
    v_before_meeting_requested boolean := coalesce(p_before.meeting_requested, false);
    v_before_speaker_ids uuid[];
    v_before_starts_at timestamptz := date_trunc('second', p_before.starts_at);
begin
    -- Parse the payload schedule in the payload timezone
    v_after_starts_at := (p_after->>'starts_at')::timestamp at time zone v_after_timezone;
    v_after_ends_at := (p_after->>'ends_at')::timestamp at time zone v_after_timezone;

    -- Load the prior host and speaker rows
    select array_agg(eh.user_id order by eh.user_id)
    into v_before_host_ids
    from event_host eh
    where eh.event_id = p_before.event_id;

    select array_agg(es.user_id order by es.user_id)
    into v_before_speaker_ids
    from event_speaker es
    where es.event_id = p_before.event_id;

    -- Collect the payload hosts (uuid strings) and speakers (objects with user_id)
    select array_agg(h order by h)
    into v_after_host_ids
    from (select h::uuid as h from jsonb_array_elements_text(p_after->'hosts') h) sub;

    select array_agg(s order by s)
    into v_after_speaker_ids
    from (select (s->>'user_id')::uuid as s from jsonb_array_elements(p_after->'speakers') s) sub;

    -- Schedule deletion work when a requested meeting is no longer requested
    if v_after_meeting_requested is distinct from true then
        return case when v_before_meeting_requested = true then false else null end;
    end if;

    -- Preserve real pending/error states instead of hiding unsynced work
    if v_before_meeting_requested = true and p_before.meeting_in_sync = false then
        return false;
    end if;

    -- Provider create/update sync is not claimed after the meeting starts
    if v_before_meeting_requested = true
       and p_before.meeting_in_sync = true
       and v_before_starts_at <= current_timestamp then
        return true;
    end if;

    -- Report whether every provider-visible field is unchanged
    return v_before_meeting_requested = true
        and v_before_ends_at is not distinct from v_after_ends_at
        and v_before_host_ids is not distinct from v_after_host_ids
        and p_before.meeting_hosts is not distinct from v_after_meeting_hosts
        and p_before.meeting_provider_id is not distinct from v_after_meeting_provider_id
        and coalesce(p_before.meeting_recording_requested, true) = v_after_meeting_recording_requested
        and p_before.name = v_after_name
        and v_before_speaker_ids is not distinct from v_after_speaker_ids
        and v_before_starts_at is not distinct from v_after_starts_at
        and p_before.timezone = v_after_timezone;
end;
$$ language plpgsql;
