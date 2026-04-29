-- get_event_meeting_sync_state_hash returns a hash of event meeting sync inputs.
create or replace function get_event_meeting_sync_state_hash(
    p_event_id uuid
) returns text as $$
    select encode(
        digest(
            jsonb_strip_nulls(jsonb_build_object(
                'canceled', e.canceled,
                'deleted', e.deleted,
                'ends_at', e.ends_at,
                'event_host_ids', (
                    select array_agg(eh.user_id order by eh.user_id)
                    from event_host eh
                    where eh.event_id = e.event_id
                ),
                'event_id', e.event_id,
                'event_speaker_ids', (
                    select array_agg(es.user_id order by es.user_id)
                    from event_speaker es
                    where es.event_id = e.event_id
                ),
                'meeting_hosts', (
                    select array_agg(meeting_host.email order by meeting_host.email)
                    from unnest(e.meeting_hosts) as meeting_host(email)
                ),
                'meeting_provider_id', e.meeting_provider_id,
                'meeting_requested', e.meeting_requested,
                'name', e.name,
                'published', e.published,
                'starts_at', e.starts_at,
                'timezone', e.timezone
            ))::text,
            'sha256'
        ),
        'hex'
    )
    from event e
    where e.event_id = p_event_id;
$$ language sql stable;
