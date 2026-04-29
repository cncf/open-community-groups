-- claim_meeting_for_auto_end claims one overdue meeting for auto-end checks.
-- It currently filters candidates to Zoom meetings.
create or replace function claim_meeting_for_auto_end()
returns jsonb as $$
declare
    v_claimed_meeting jsonb;
begin
    -- Lock and claim one eligible overdue event-backed meeting first
    with next_meeting as (
        select
            m.meeting_id,
            e.ends_at
        from meeting m
        join event e on e.event_id = m.event_id
        where m.auto_end_check_at is null
          and m.auto_end_check_claimed_at is null
          and m.meeting_provider_id = 'zoom'
          and e.canceled = false
          and e.deleted = false
          and e.ends_at is not null
          and e.meeting_in_sync = true
          and e.meeting_requested = true
          and e.published = true
          and e.ends_at + interval '10 minutes' <= current_timestamp
        order by e.ends_at desc
        for update of m skip locked
        limit 1
    ),
    claimed_meeting as (
        update meeting m
        set
            auto_end_check_claimed_at = current_timestamp,
            updated_at = current_timestamp
        from next_meeting nm
        where m.meeting_id = nm.meeting_id
        returning
            m.meeting_id,
            m.meeting_provider_id,
            m.provider_meeting_id
    )
    select
        jsonb_build_object(
            'meeting_id', cm.meeting_id,
            'meeting_provider_id', cm.meeting_provider_id,
            'provider_meeting_id', cm.provider_meeting_id
        )
    into v_claimed_meeting
    from claimed_meeting cm;

    if v_claimed_meeting is not null then
        return v_claimed_meeting;
    end if;

    -- If no event-backed meeting is eligible, claim one session-backed meeting
    with next_meeting as (
        select
            m.meeting_id,
            s.ends_at
        from meeting m
        join session s on s.session_id = m.session_id
        join event e on e.event_id = s.event_id
        where m.auto_end_check_at is null
          and m.auto_end_check_claimed_at is null
          and m.meeting_provider_id = 'zoom'
          and s.meeting_in_sync = true
          and s.meeting_requested = true
          and s.ends_at is not null
          and e.canceled = false
          and e.deleted = false
          and e.published = true
          and s.ends_at + interval '10 minutes' <= current_timestamp
        order by s.ends_at desc
        for update of m skip locked
        limit 1
    ),
    claimed_meeting as (
        update meeting m
        set
            auto_end_check_claimed_at = current_timestamp,
            updated_at = current_timestamp
        from next_meeting nm
        where m.meeting_id = nm.meeting_id
        returning
            m.meeting_id,
            m.meeting_provider_id,
            m.provider_meeting_id
    )
    select
        jsonb_build_object(
            'meeting_id', cm.meeting_id,
            'meeting_provider_id', cm.meeting_provider_id,
            'provider_meeting_id', cm.provider_meeting_id
        )
    into v_claimed_meeting
    from claimed_meeting cm;

    return v_claimed_meeting;
end;
$$ language plpgsql;
