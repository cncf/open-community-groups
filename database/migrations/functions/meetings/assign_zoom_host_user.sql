-- assign_zoom_host_user reserves one available host user for a Zoom meeting.
drop function if exists assign_zoom_host_user(uuid, uuid, text[], integer, timestamptz, timestamptz);
create or replace function assign_zoom_host_user(
    p_event_id uuid,
    p_session_id uuid,
    p_sync_claimed_at timestamptz,
    p_pool_users text[],
    p_max_simultaneous_meetings_per_user integer,
    p_starts_at timestamptz,
    p_ends_at timestamptz
) returns text as $$
declare
    v_provider_host_user_id text;
begin
    -- Guard clause for invalid input
    if p_max_simultaneous_meetings_per_user < 1
       or p_starts_at is null
       or p_ends_at is null
       or p_ends_at <= p_starts_at
       or array_length(p_pool_users, 1) is null
       or (p_event_id is null and p_session_id is null) then
        return null;
    end if;

    -- Serialize host allocation while persisting the reservation
    perform pg_advisory_xact_lock(hashtextextended('ocg:zoom-host-slot-allocation', 0));

    -- Select the least-loaded host with an available overlapping slot
    with host_load as (
        select
            lower(provider_host_user_id) as user_email,
            count(*) filter (
                where tstzrange(
                    starts_at - interval '15 minutes',
                    ends_at + interval '15 minutes',
                    '[)'
                ) && tstzrange(p_starts_at, p_ends_at, '[)')
            ) as overlapping_meetings,
            count(*) filter (
                where ends_at >= current_timestamp
            ) as upcoming_meetings
        from (
            -- Count host slots already persisted on provider meetings
            select
                m.provider_host_user_id,
                coalesce(e.starts_at, s.starts_at) as starts_at,
                coalesce(e.ends_at, s.ends_at) as ends_at
            from meeting m
            left join event e on e.event_id = m.event_id
            left join session s on s.session_id = m.session_id
            where m.meeting_provider_id = 'zoom'
              and m.provider_host_user_id is not null
              and coalesce(e.starts_at, s.starts_at) is not null
              and coalesce(e.ends_at, s.ends_at) is not null

            union all

            -- Count event host reservations made by claimed sync workers
            select
                e.meeting_provider_host_user,
                e.starts_at,
                e.ends_at
            from event e
            where e.meeting_provider_id = 'zoom'
              and e.meeting_provider_host_user is not null
              and e.meeting_sync_claimed_at is not null
              and e.meeting_in_sync = false
              and e.starts_at is not null
              and e.ends_at is not null

            union all

            -- Count session host reservations made by claimed sync workers
            select
                s.meeting_provider_host_user,
                s.starts_at,
                s.ends_at
            from session s
            where s.meeting_provider_id = 'zoom'
              and s.meeting_provider_host_user is not null
              and s.meeting_sync_claimed_at is not null
              and s.meeting_in_sync = false
              and s.starts_at is not null
              and s.ends_at is not null
        ) reserved
        group by lower(provider_host_user_id)
    ),
    pool as (
        select distinct lower(btrim(pool_user)) as user_email
        from unnest(p_pool_users) as pool_user
        where pool_user is not null
          and btrim(pool_user) <> ''
    )
    select p.user_email
    into v_provider_host_user_id
    from pool p
    left join host_load hl using (user_email)
    where coalesce(hl.overlapping_meetings, 0) < p_max_simultaneous_meetings_per_user
    order by
        coalesce(hl.overlapping_meetings, 0),
        coalesce(hl.upcoming_meetings, 0),
        p.user_email
    limit 1;

    -- Return early when no host is available
    if v_provider_host_user_id is null then
        return null;
    end if;

    -- Return selection-only results without persisting a reservation
    if p_sync_claimed_at is null then
        return v_provider_host_user_id;
    end if;

    -- Store the selected host only on the matching claim
    if p_event_id is not null then
        update event
        set meeting_provider_host_user = v_provider_host_user_id
        where event_id = p_event_id
          and meeting_sync_claimed_at = p_sync_claimed_at;
    elsif p_session_id is not null then
        update session
        set meeting_provider_host_user = v_provider_host_user_id
        where session_id = p_session_id
          and meeting_sync_claimed_at = p_sync_claimed_at;
    end if;

    -- Return null when the selected host was not reserved on the current claim
    if not found then
        return null;
    end if;

    return v_provider_host_user_id;
end;
$$ language plpgsql;
