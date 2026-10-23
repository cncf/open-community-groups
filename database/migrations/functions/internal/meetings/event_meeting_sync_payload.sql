-- Builds the meeting sync claim payload (the Rust Meeting DTO) for an event;
-- delete payloads target the provider of the stored meeting.
create or replace function event_meeting_sync_payload(
    p_event event,
    p_delete boolean
)
returns jsonb as $$
    select jsonb_strip_nulls(
        jsonb_build_object(
            'delete', p_delete,
            'event_id', p_event.event_id,
            'join_url', m.join_url,
            'meeting_id', m.meeting_id,
            'password', m.password,
            'provider_host_user_id', p_event.meeting_provider_host_user,
            'provider_meeting_id', m.provider_meeting_id,
            'sync_claimed_at', p_event.meeting_sync_claimed_at,
            'sync_state_hash', get_event_meeting_sync_state_hash(p_event.event_id)
        )
        || case
            -- Delete payloads target the provider of the stored meeting
            when p_delete then jsonb_build_object(
                'meeting_provider_id', m.meeting_provider_id
            )
            -- Create and update payloads carry the meeting settings and combined hosts
            else jsonb_build_object(
                'duration_secs', extract(epoch from p_event.ends_at - p_event.starts_at)::double precision,
                'hosts', (
                    select array_agg(distinct email order by email) filter (where email is not null)
                    from (
                        select unnest(p_event.meeting_hosts) as email
                        union
                        select u.email from event_host eh join "user" u using (user_id) where eh.event_id = p_event.event_id
                        union
                        select u.email from event_speaker es join "user" u using (user_id) where es.event_id = p_event.event_id
                    ) combined
                ),
                'meeting_provider_id', p_event.meeting_provider_id,
                'meeting_recording_requested', p_event.meeting_recording_requested,
                'starts_at', p_event.starts_at,
                'timezone', p_event.timezone,
                'topic', p_event.name
            )
        end
    )
    from (select 1) one
    left join meeting m on m.event_id = p_event.event_id;
$$ language sql stable;
