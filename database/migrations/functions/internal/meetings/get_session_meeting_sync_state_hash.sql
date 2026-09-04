-- get_session_meeting_sync_state_hash returns a hash of session meeting sync inputs.
create or replace function get_session_meeting_sync_state_hash(
    p_session_id uuid
) returns text as $$
    select encode(
        digest(
            jsonb_strip_nulls(jsonb_build_object(
                'event_canceled', e.canceled,
                'event_deleted', e.deleted,
                'event_host_ids', (
                    select array_agg(eh.user_id order by eh.user_id)
                    from event_host eh
                    where eh.event_id = e.event_id
                ),
                'event_published', e.published,
                'event_meeting_recording_requested', e.meeting_recording_requested,
                'event_timezone', e.timezone,
                'ends_at', s.ends_at,
                'meeting_hosts', (
                    select array_agg(meeting_host.email order by meeting_host.email)
                    from unnest(s.meeting_hosts) as meeting_host(email)
                ),
                'meeting_provider_id', s.meeting_provider_id,
                'meeting_requested', s.meeting_requested,
                'name', s.name,
                'session_id', s.session_id,
                'session_kind_id', s.session_kind_id,
                'session_speaker_ids', (
                    select array_agg(ss.user_id order by ss.user_id)
                    from session_speaker ss
                    where ss.session_id = s.session_id
                ),
                'starts_at', s.starts_at
            ))::text,
            'sha256'
        ),
        'hex'
    )
    from session s
    join event e on e.event_id = s.event_id
    where s.session_id = p_session_id;
$$ language sql stable;
