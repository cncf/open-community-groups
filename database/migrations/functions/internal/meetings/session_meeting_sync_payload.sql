-- Builds the meeting sync claim payload (the Rust Meeting DTO) for a session;
-- delete payloads target the provider of the stored meeting.
create or replace function session_meeting_sync_payload(
    p_session session,
    p_delete boolean
)
returns jsonb as $$
    select jsonb_strip_nulls(
        jsonb_build_object(
            'delete', p_delete,
            'join_url', m.join_url,
            'meeting_id', m.meeting_id,
            'password', m.password,
            'provider_host_user_id', p_session.meeting_provider_host_user,
            'provider_meeting_id', m.provider_meeting_id,
            'session_id', p_session.session_id,
            'sync_claimed_at', p_session.meeting_sync_claimed_at,
            'sync_state_hash', get_session_meeting_sync_state_hash(p_session.session_id)
        )
        || case
            -- Delete payloads target the provider of the stored meeting
            when p_delete then jsonb_build_object(
                'meeting_provider_id', m.meeting_provider_id
            )
            -- Create and update payloads carry the meeting settings and combined hosts
            else jsonb_build_object(
                'duration_secs', extract(epoch from p_session.ends_at - p_session.starts_at)::double precision,
                'hosts', (
                    select array_agg(distinct email order by email) filter (where email is not null)
                    from (
                        select unnest(p_session.meeting_hosts) as email
                        union
                        select u.email from event_host eh join "user" u using (user_id) where eh.event_id = p_session.event_id
                        union
                        select u.email from session_speaker ss join "user" u using (user_id) where ss.session_id = p_session.session_id
                    ) combined
                ),
                'meeting_provider_id', p_session.meeting_provider_id,
                'meeting_recording_requested', e.meeting_recording_requested,
                'starts_at', p_session.starts_at,
                'timezone', e.timezone,
                'topic', p_session.name
            )
        end
    )
    from (select 1) one
    join event e on e.event_id = p_session.event_id
    left join meeting m on m.session_id = p_session.session_id;
$$ language sql stable;
