-- claim_meeting_out_of_sync claims one meeting that needs synchronization.
create or replace function claim_meeting_out_of_sync()
returns jsonb as $$
declare
    v_claimed_meeting jsonb;
    v_event event;
    v_event_id uuid;
    v_has_meeting boolean;
    v_prior_create_attempted_at timestamptz;
    v_session session;
    v_session_id uuid;
begin
    -- Case 1: Event needing create/update
    select
        e.event_id,
        e.meeting_create_attempted_at
    into
        v_event_id,
        v_prior_create_attempted_at
    from event e
    where e.meeting_requested = true
      and e.meeting_in_sync = false
      and e.meeting_sync_claimed_at is null
      and (
          e.meeting_next_sync_at is null
          or e.meeting_next_sync_at <= current_timestamp
      )
      and e.deleted = false
      and e.canceled = false
      and e.published = true
      and e.starts_at > current_timestamp
    for update of e skip locked
    limit 1;

    -- Claim the locked event and return its create/update payload
    if found then
        -- Check after locking whether a persisted meeting row already exists
        v_has_meeting := exists (
            select 1
            from meeting m
            where m.event_id = v_event_id
        );

        -- Persist the claim, attempt count and monotonic create-attempt timestamp
        update event e
        set
            meeting_create_attempted_at = case
                -- Stamp create-attempt tracking durably before any provider create call
                when not v_has_meeting then coalesce(e.meeting_create_attempted_at, current_timestamp)
                -- Preserve existing create tracking when updating a stored meeting
                else e.meeting_create_attempted_at
            end,
            meeting_error = null,
            meeting_next_sync_at = null,
            meeting_sync_attempts = e.meeting_sync_attempts + 1,
            meeting_sync_claimed_at = current_timestamp
        where e.event_id = v_event_id
        returning e.* into v_event;

        -- Report the pre-claim create attempt timestamp so only retries scan the provider
        v_event.meeting_create_attempted_at := v_prior_create_attempted_at;
        return event_meeting_sync_payload(v_event, false);
    end if;

    -- Case 2: Session needing create/update
    select
        s.session_id,
        s.meeting_create_attempted_at
    into
        v_session_id,
        v_prior_create_attempted_at
    from session s
    join event e on e.event_id = s.event_id
    where s.meeting_requested = true
      and s.meeting_in_sync = false
      and s.meeting_sync_claimed_at is null
      and (
          s.meeting_next_sync_at is null
          or s.meeting_next_sync_at <= current_timestamp
      )
      and e.deleted = false
      and e.canceled = false
      and e.published = true
      and s.starts_at > current_timestamp
    for update of s skip locked
    limit 1;

    -- Claim the locked session and return its create/update payload
    if found then
        -- Check after locking whether a persisted meeting row already exists
        v_has_meeting := exists (
            select 1
            from meeting m
            where m.session_id = v_session_id
        );

        -- Persist the claim, attempt count and monotonic create-attempt timestamp
        update session s
        set
            meeting_create_attempted_at = case
                -- Stamp create-attempt tracking durably before any provider create call
                when not v_has_meeting then coalesce(s.meeting_create_attempted_at, current_timestamp)
                -- Preserve existing create tracking when updating a stored meeting
                else s.meeting_create_attempted_at
            end,
            meeting_error = null,
            meeting_next_sync_at = null,
            meeting_sync_attempts = s.meeting_sync_attempts + 1,
            meeting_sync_claimed_at = current_timestamp
        where s.session_id = v_session_id
        returning s.* into v_session;

        -- Report the pre-claim create attempt timestamp so only retries scan the provider
        v_session.meeting_create_attempted_at := v_prior_create_attempted_at;
        return session_meeting_sync_payload(v_session, false);
    end if;

    -- Case 3: Event needing delete
    with next_event as (
        select e.event_id
        from event e
        where e.meeting_in_sync = false
          and e.meeting_sync_claimed_at is null
          and (
              e.meeting_next_sync_at is null
              or e.meeting_next_sync_at <= current_timestamp
          )
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
        meeting_next_sync_at = null,
        meeting_sync_attempts = e.meeting_sync_attempts + 1,
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
              s.meeting_next_sync_at is null
              or s.meeting_next_sync_at <= current_timestamp
          )
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
        meeting_next_sync_at = null,
        meeting_sync_attempts = s.meeting_sync_attempts + 1,
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
          and (
              m.next_sync_at is null
              or m.next_sync_at <= current_timestamp
          )
        for update skip locked
        limit 1
    ),
    claimed_meeting as (
        update meeting m
        set
            next_sync_at = null,
            sync_attempts = m.sync_attempts + 1,
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
        'sync_attempts', cm.sync_attempts,
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
