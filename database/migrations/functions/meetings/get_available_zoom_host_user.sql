-- get_available_zoom_host_user returns one available host user for a Zoom meeting.
create or replace function get_available_zoom_host_user(
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
       or array_length(p_pool_users, 1) is null then
        return null;
    end if;

    -- Serialize host allocation to avoid races across workers
    perform pg_advisory_xact_lock(hashtext('zoom_host_slot_allocation')::bigint);

    -- Select the least-loaded host with an available overlapping slot
    with host_load as (
        select
            lower(m.provider_host_user_id) as user_email,
            count(*) filter (
                where tstzrange(
                    coalesce(e.starts_at, s.starts_at) - interval '15 minutes',
                    coalesce(e.ends_at, s.ends_at) + interval '15 minutes',
                    '[)'
                ) && tstzrange(p_starts_at, p_ends_at, '[)')
            ) as overlapping_meetings,
            count(*) filter (
                where coalesce(e.ends_at, s.ends_at) >= current_timestamp
            ) as upcoming_meetings
        from meeting m
        left join event e on e.event_id = m.event_id
        left join session s on s.session_id = m.session_id
        where m.meeting_provider_id = 'zoom'
          and m.provider_host_user_id is not null
          and coalesce(e.starts_at, s.starts_at) is not null
          and coalesce(e.ends_at, s.ends_at) is not null
        group by lower(m.provider_host_user_id)
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

    return v_provider_host_user_id;
end;
$$ language plpgsql;
