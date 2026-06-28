-- claim_google_meet_recording_for_publish claims one completed Google Meet
-- meeting whose recording should be searched for and uploaded to YouTube.
create or replace function claim_google_meet_recording_for_publish(
    p_publish_delay_seconds bigint,
    p_retry_delay_seconds bigint
) returns jsonb as $$
declare
    v_claimed_meeting jsonb;
begin
    -- Case 1: Event meeting.
    with next_event_meeting as (
        select m.meeting_id
        from meeting m
        join event e on e.event_id = m.event_id
        where m.meeting_provider_id = 'google_meet'
          and m.recording_publish_claimed_at is null
          and m.recording_publish_url is null
          and (
              m.recording_publish_checked_at is null
              or m.recording_publish_checked_at <= current_timestamp - (p_retry_delay_seconds::text || ' seconds')::interval
          )
          and e.meeting_recording_requested = true
          and e.meeting_recording_url is null
          and e.meeting_recording_published = false
          and e.deleted = false
          and e.canceled = false
          and e.published = true
          and e.ends_at <= current_timestamp - (p_publish_delay_seconds::text || ' seconds')::interval
        order by e.ends_at
        for update of m skip locked
        limit 1
    ),
    claimed_meeting as (
        update meeting m
        set recording_publish_claimed_at = current_timestamp,
            recording_publish_error = null,
            updated_at = current_timestamp
        from next_event_meeting nem
        where m.meeting_id = nem.meeting_id
        returning m.*
    )
    select jsonb_strip_nulls(jsonb_build_object(
        'ends_at', e.ends_at,
        'event_id', e.event_id,
        'meeting_id', cm.meeting_id,
        'provider_meeting_id', cm.provider_meeting_id,
        'recording_publish_claimed_at', cm.recording_publish_claimed_at,
        'starts_at', e.starts_at,
        'timezone', e.timezone,
        'topic', e.name
    ))
    into v_claimed_meeting
    from claimed_meeting cm
    join event e on e.event_id = cm.event_id;

    if v_claimed_meeting is not null then
        return v_claimed_meeting;
    end if;

    -- Case 2: Session meeting. Sessions inherit recording_requested from the event.
    with next_session_meeting as (
        select m.meeting_id
        from meeting m
        join session s on s.session_id = m.session_id
        join event e on e.event_id = s.event_id
        where m.meeting_provider_id = 'google_meet'
          and m.recording_publish_claimed_at is null
          and m.recording_publish_url is null
          and (
              m.recording_publish_checked_at is null
              or m.recording_publish_checked_at <= current_timestamp - (p_retry_delay_seconds::text || ' seconds')::interval
          )
          and e.meeting_recording_requested = true
          and s.meeting_recording_url is null
          and s.meeting_recording_published = false
          and e.deleted = false
          and e.canceled = false
          and e.published = true
          and s.ends_at <= current_timestamp - (p_publish_delay_seconds::text || ' seconds')::interval
        order by s.ends_at
        for update of m skip locked
        limit 1
    ),
    claimed_meeting as (
        update meeting m
        set recording_publish_claimed_at = current_timestamp,
            recording_publish_error = null,
            updated_at = current_timestamp
        from next_session_meeting nsm
        where m.meeting_id = nsm.meeting_id
        returning m.*
    )
    select jsonb_strip_nulls(jsonb_build_object(
        'ends_at', s.ends_at,
        'meeting_id', cm.meeting_id,
        'provider_meeting_id', cm.provider_meeting_id,
        'recording_publish_claimed_at', cm.recording_publish_claimed_at,
        'session_id', s.session_id,
        'starts_at', s.starts_at,
        'timezone', e.timezone,
        'topic', s.name
    ))
    into v_claimed_meeting
    from claimed_meeting cm
    join session s on s.session_id = cm.session_id
    join event e on e.event_id = s.event_id;

    if v_claimed_meeting is not null then
        return v_claimed_meeting;
    end if;

    return null;
end;
$$ language plpgsql;
