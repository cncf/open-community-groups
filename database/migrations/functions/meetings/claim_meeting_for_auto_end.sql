-- claim_meeting_for_auto_end claims one overdue meeting for auto-end checks.
-- It currently filters candidates to Zoom meetings.
create or replace function claim_meeting_for_auto_end()
returns jsonb as $$
declare
    v_claimed_meeting jsonb;
    v_meeting_id uuid;
begin
    -- Pick the most recently overdue eligible event-backed meeting first
    select m.meeting_id
    into v_meeting_id
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
    limit 1;

    -- Fall back to the most recently overdue eligible session-backed meeting
    if v_meeting_id is null then
        select m.meeting_id
        into v_meeting_id
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
        limit 1;
    end if;

    -- Return nothing when no meeting is due
    if v_meeting_id is null then
        return null;
    end if;

    -- Claim the selected meeting and return its claim payload
    update meeting m
    set
        auto_end_check_claimed_at = current_timestamp,
        updated_at = current_timestamp
    where m.meeting_id = v_meeting_id
    returning jsonb_build_object(
        'auto_end_check_claimed_at', m.auto_end_check_claimed_at,
        'meeting_id', m.meeting_id,
        'meeting_provider_id', m.meeting_provider_id,
        'provider_meeting_id', m.provider_meeting_id
    )
    into v_claimed_meeting;

    return v_claimed_meeting;
end;
$$ language plpgsql;
