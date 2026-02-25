-- get_meeting_for_auto_end returns one overdue meeting for auto-end checks.
-- It currently filters candidates to Zoom meetings.
create or replace function get_meeting_for_auto_end()
returns table (
    meeting_id uuid,
    meeting_provider_id text,
    provider_meeting_id text
) as $$
begin
    -- Lock and return one eligible overdue event-backed meeting first
    return query
    select
        m.meeting_id,
        m.meeting_provider_id,
        m.provider_meeting_id
    from meeting m
    join event e on e.event_id = m.event_id
    where m.meeting_provider_id = 'zoom'
      and m.auto_end_check_at is null
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

    if found then
        return;
    end if;

    -- If no event-backed meeting is eligible, lock and return one session-backed meeting
    return query
    select
        m.meeting_id,
        m.meeting_provider_id,
        m.provider_meeting_id
    from meeting m
    join session s on s.session_id = m.session_id
    join event e on e.event_id = s.event_id
    where m.meeting_provider_id = 'zoom'
      and m.auto_end_check_at is null
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
end;
$$ language plpgsql;
