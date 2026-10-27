-- claim_meeting_out_of_sync claims one meeting that needs synchronization.
create or replace function claim_meeting_out_of_sync()
returns jsonb as $$
declare
    v_claimed_meeting jsonb;
    v_event event;
    v_session session;
begin
    -- Case 1: Event needing create/update
    with next_event as (
        select e.event_id
        from event e
        where e.meeting_requested = true
          and e.meeting_in_sync = false
          and e.meeting_sync_claimed_at is null
          and e.deleted = false
          and e.canceled = false
          and e.published = true
          and e.starts_at > current_timestamp
        for update skip locked
        limit 1
    )
    update event e
    set
        meeting_error = null,
        meeting_sync_claimed_at = current_timestamp
    from next_event ne
    where e.event_id = ne.event_id
    returning e.* into v_event;

    -- Return the claimed event's create/update payload
    if found then
        return event_meeting_sync_payload(v_event, false);
    end if;

    -- Case 2: Session needing create/update
    with next_session as (
        select s.session_id
        from session s
        join event e on e.event_id = s.event_id
        where s.meeting_requested = true
          and s.meeting_in_sync = false
          and s.meeting_sync_claimed_at is null
          and e.deleted = false
          and e.canceled = false
          and e.published = true
          and s.starts_at > current_timestamp
        for update of s skip locked
        limit 1
    )
    update session s
    set
        meeting_error = null,
        meeting_sync_claimed_at = current_timestamp
    from next_session ns
    where s.session_id = ns.session_id
    returning s.* into v_session;

    -- Return the claimed session's create/update payload
    if found then
        return session_meeting_sync_payload(v_session, false);
    end if;

    -- Case 3: Event needing delete
    with next_event as (
        select e.event_id
        from event e
        where e.meeting_in_sync = false
          and e.meeting_sync_claimed_at is null
          and (
              (e.meeting_requested = true and (e.deleted = true or e.canceled = true or e.published = false))
              or e.meeting_requested is distinct from true
          )
        for update of e skip locked
        limit 1
    )
    update event e
    set
        meeting_error = null,
        meeting_sync_claimed_at = current_timestamp
    from next_event ne
    where e.event_id = ne.event_id
    returning e.* into v_event;

    -- Return the claimed event's delete payload
    if found then
        return event_meeting_sync_payload(v_event, true);
    end if;

    -- Case 4: Session needing delete
    with next_session as (
        select s.session_id
        from session s
        join event e on e.event_id = s.event_id
        where s.meeting_in_sync = false
          and s.meeting_sync_claimed_at is null
          and (
            (s.meeting_requested = true and (e.deleted = true or e.canceled = true or e.published = false))
            or s.meeting_requested is distinct from true
          )
        for update of s skip locked
        limit 1
    )
    update session s
    set
        meeting_error = null,
        meeting_sync_claimed_at = current_timestamp
    from next_session ns
    where s.session_id = ns.session_id
    returning s.* into v_session;

    -- Return the claimed session's delete payload
    if found then
        return session_meeting_sync_payload(v_session, true);
    end if;

    -- Case 5: Orphan meetings
    with next_meeting as (
        select m.meeting_id
        from meeting m
        where m.event_id is null
          and m.session_id is null
          and m.sync_claimed_at is null
        for update skip locked
        limit 1
    ),
    claimed_meeting as (
        update meeting m
        set
            sync_claimed_at = current_timestamp,
            updated_at = current_timestamp
        from next_meeting nm
        where m.meeting_id = nm.meeting_id
        returning m.*
    )
    select jsonb_strip_nulls(jsonb_build_object(
        'delete', true,
        'join_url', cm.join_url,
        'meeting_id', cm.meeting_id,
        'meeting_provider_id', cm.meeting_provider_id,
        'password', cm.password,
        'provider_host_user_id', cm.provider_host_user_id,
        'provider_meeting_id', cm.provider_meeting_id,
        'sync_claimed_at', cm.sync_claimed_at
    ))
    into v_claimed_meeting
    from claimed_meeting cm;

    -- Return the claimed orphan meeting's delete payload
    if v_claimed_meeting is not null then
        return v_claimed_meeting;
    end if;

    -- Report that no meeting needs synchronization
    return null;
end;
$$ language plpgsql;
