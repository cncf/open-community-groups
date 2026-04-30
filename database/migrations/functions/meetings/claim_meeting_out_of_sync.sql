-- claim_meeting_out_of_sync claims one meeting that needs synchronization.
drop function if exists claim_meeting_out_of_sync();
create or replace function claim_meeting_out_of_sync()
returns jsonb as $$
declare
    v_claimed_event_id uuid;
    v_claimed_meeting_id uuid;
    v_claimed_session_id uuid;
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
    ),
    claimed_event as (
        update event e
        set
            meeting_error = null,
            meeting_sync_claimed_at = current_timestamp
        from next_event ne
        where e.event_id = ne.event_id
        returning e.event_id
    )
    select ce.event_id into v_claimed_event_id from claimed_event ce;

    if v_claimed_event_id is not null then
        return (
            select jsonb_strip_nulls(jsonb_build_object(
                'delete', false,
                'duration_secs', extract(epoch from e.ends_at - e.starts_at)::double precision,
                'event_id', e.event_id,
                'hosts', (
                    select array_agg(distinct email order by email) filter (where email is not null)
                    from (
                        select unnest(e.meeting_hosts) as email
                        union
                        select u.email from event_host eh join "user" u using (user_id) where eh.event_id = e.event_id
                        union
                        select u.email from event_speaker es join "user" u using (user_id) where es.event_id = e.event_id
                    ) combined
                ),
                'join_url', m.join_url,
                'meeting_id', m.meeting_id,
                'meeting_provider_id', e.meeting_provider_id,
                'password', m.password,
                'provider_host_user_id', e.meeting_provider_host_user,
                'provider_meeting_id', m.provider_meeting_id,
                'session_id', null::uuid,
                'starts_at', e.starts_at,
                'sync_claimed_at', e.meeting_sync_claimed_at,
                'sync_state_hash', get_event_meeting_sync_state_hash(e.event_id),
                'timezone', e.timezone,
                'topic', e.name
            ))
        from event e
        left join meeting m on m.event_id = e.event_id
        where e.event_id = v_claimed_event_id
        );
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
    ),
    claimed_session as (
        update session s
        set
            meeting_error = null,
            meeting_sync_claimed_at = current_timestamp
        from next_session ns
        where s.session_id = ns.session_id
        returning s.session_id
    )
    select cs.session_id into v_claimed_session_id from claimed_session cs;

    if v_claimed_session_id is not null then
        return (
            select jsonb_strip_nulls(jsonb_build_object(
                'delete', false,
                'duration_secs', extract(epoch from s.ends_at - s.starts_at)::double precision,
                'event_id', null::uuid,
                'hosts', (
                    select array_agg(distinct email order by email) filter (where email is not null)
                    from (
                        select unnest(s.meeting_hosts) as email
                        union
                        select u.email from event_host eh join "user" u using (user_id) where eh.event_id = s.event_id
                        union
                        select u.email from session_speaker ss join "user" u using (user_id) where ss.session_id = s.session_id
                    ) combined
                ),
                'join_url', m.join_url,
                'meeting_id', m.meeting_id,
                'meeting_provider_id', s.meeting_provider_id,
                'password', m.password,
                'provider_host_user_id', s.meeting_provider_host_user,
                'provider_meeting_id', m.provider_meeting_id,
                'session_id', s.session_id,
                'starts_at', s.starts_at,
                'sync_claimed_at', s.meeting_sync_claimed_at,
                'sync_state_hash', get_session_meeting_sync_state_hash(s.session_id),
                'timezone', e.timezone,
                'topic', s.name
            ))
        from session s
        join event e on e.event_id = s.event_id
        left join meeting m on m.session_id = s.session_id
        where s.session_id = v_claimed_session_id
        );
    end if;

    -- Case 3: Event needing delete
    with next_event as (
        select e.event_id
        from event e
        left join meeting m on m.event_id = e.event_id
        where e.meeting_in_sync = false
          and e.meeting_sync_claimed_at is null
          and (
              (e.meeting_requested = true and (e.deleted = true or e.canceled = true or e.published = false))
              or e.meeting_requested = false
          )
        for update of e skip locked
        limit 1
    ),
    claimed_event as (
        update event e
        set
            meeting_error = null,
            meeting_sync_claimed_at = current_timestamp
        from next_event ne
        where e.event_id = ne.event_id
        returning e.event_id
    )
    select ce.event_id into v_claimed_event_id from claimed_event ce;

    if v_claimed_event_id is not null then
        return (
            select jsonb_strip_nulls(jsonb_build_object(
                'delete', true,
                'duration_secs', null::double precision,
                'event_id', e.event_id,
                'hosts', null::text[],
                'join_url', m.join_url,
                'meeting_id', m.meeting_id,
                'meeting_provider_id', m.meeting_provider_id,
                'password', m.password,
                'provider_host_user_id', e.meeting_provider_host_user,
                'provider_meeting_id', m.provider_meeting_id,
                'session_id', null::uuid,
                'starts_at', null::timestamptz,
                'sync_claimed_at', e.meeting_sync_claimed_at,
                'sync_state_hash', get_event_meeting_sync_state_hash(e.event_id),
                'timezone', null::text,
                'topic', null::text
            ))
        from event e
        left join meeting m on m.event_id = e.event_id
        where e.event_id = v_claimed_event_id
        );
    end if;

    -- Case 4: Session needing delete
    with next_session as (
        select s.session_id
        from session s
        join event e on e.event_id = s.event_id
        left join meeting m on m.session_id = s.session_id
        where s.meeting_in_sync = false
          and s.meeting_sync_claimed_at is null
          and (
            (s.meeting_requested = true and (e.deleted = true or e.canceled = true or e.published = false))
            or s.meeting_requested = false
          )
        for update of s skip locked
        limit 1
    ),
    claimed_session as (
        update session s
        set
            meeting_error = null,
            meeting_sync_claimed_at = current_timestamp
        from next_session ns
        where s.session_id = ns.session_id
        returning s.session_id
    )
    select cs.session_id into v_claimed_session_id from claimed_session cs;

    if v_claimed_session_id is not null then
        return (
            select jsonb_strip_nulls(jsonb_build_object(
                'delete', true,
                'duration_secs', null::double precision,
                'event_id', null::uuid,
                'hosts', null::text[],
                'join_url', m.join_url,
                'meeting_id', m.meeting_id,
                'meeting_provider_id', m.meeting_provider_id,
                'password', m.password,
                'provider_host_user_id', s.meeting_provider_host_user,
                'provider_meeting_id', m.provider_meeting_id,
                'session_id', s.session_id,
                'starts_at', null::timestamptz,
                'sync_claimed_at', s.meeting_sync_claimed_at,
                'sync_state_hash', get_session_meeting_sync_state_hash(s.session_id),
                'timezone', null::text,
                'topic', null::text
            ))
        from session s
        left join meeting m on m.session_id = s.session_id
        where s.session_id = v_claimed_session_id
        );
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
        returning m.meeting_id
    )
    select cm.meeting_id into v_claimed_meeting_id from claimed_meeting cm;

    if v_claimed_meeting_id is not null then
        return (
            select jsonb_strip_nulls(jsonb_build_object(
                'delete', true,
                'duration_secs', null::double precision,
                'event_id', null::uuid,
                'hosts', null::text[],
                'join_url', m.join_url,
                'meeting_id', m.meeting_id,
                'meeting_provider_id', m.meeting_provider_id,
                'password', m.password,
                'provider_host_user_id', m.provider_host_user_id,
                'provider_meeting_id', m.provider_meeting_id,
                'session_id', null::uuid,
                'starts_at', null::timestamptz,
                'sync_claimed_at', m.sync_claimed_at,
                'timezone', null::text,
                'topic', null::text
            ))
        from meeting m
        where m.meeting_id = v_claimed_meeting_id
        );
    end if;

    return null;
end;
$$ language plpgsql;
