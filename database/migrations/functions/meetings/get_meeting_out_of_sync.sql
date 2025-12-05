-- get_meeting_out_of_sync returns one meeting that needs synchronization with the provider.
create or replace function get_meeting_out_of_sync()
returns table (
    delete boolean,
    duration_secs double precision,
    event_id uuid,
    hosts text[],
    join_url text,
    meeting_id uuid,
    meeting_provider_id text,
    password text,
    provider_meeting_id text,
    requires_password boolean,
    session_id uuid,
    starts_at timestamptz,
    timezone text,
    topic text
) as $$
declare
    v_event_id uuid;
    v_session_id uuid;
begin
    -- Case 1: Event needing create/update (published, not deleted/canceled)
    -- Priority: create/update operations come before deletes
    select e.event_id into v_event_id
    from event e
    where e.meeting_requested = true
      and e.meeting_in_sync = false
      and e.deleted = false
      and e.canceled = false
      and e.published = true
    for update skip locked
    limit 1;

    if v_event_id is not null then
        return query
        select
            false as delete,
            extract(epoch from e.ends_at - e.starts_at)::double precision as duration_secs,
            e.event_id,
            e.meeting_hosts as hosts,
            m.join_url,
            m.meeting_id,
            e.meeting_provider_id,
            m.password,
            m.provider_meeting_id,
            e.meeting_requires_password as requires_password,
            null::uuid as session_id,
            e.starts_at,
            e.timezone,
            e.name as topic
        from event e
        left join meeting m on m.event_id = e.event_id
        where e.event_id = v_event_id;
        return;
    end if;

    -- Case 2: Session needing create/update (parent event published and active)
    -- Priority: create/update operations come before deletes
    select s.session_id into v_session_id
    from session s
    join event e on e.event_id = s.event_id
    where s.meeting_requested = true
      and s.meeting_in_sync = false
      and e.deleted = false
      and e.canceled = false
      and e.published = true
    for update of s skip locked
    limit 1;

    if v_session_id is not null then
        return query
        select
            false as delete,
            extract(epoch from s.ends_at - s.starts_at)::double precision as duration_secs,
            null::uuid as event_id,
            s.meeting_hosts as hosts,
            m.join_url,
            m.meeting_id,
            s.meeting_provider_id,
            m.password,
            m.provider_meeting_id,
            s.meeting_requires_password as requires_password,
            s.session_id,
            s.starts_at,
            e.timezone,
            s.name as topic
        from session s
        join event e on e.event_id = s.event_id
        left join meeting m on m.session_id = s.session_id
        where s.session_id = v_session_id;
        return;
    end if;

    -- Case 3: Event needing delete (deleted, canceled, unpublished, or meeting disabled)
    select e.event_id into v_event_id
    from event e
    left join meeting m on m.event_id = e.event_id
    where e.meeting_in_sync = false
      and (
          (e.meeting_requested = true and (e.deleted = true or e.canceled = true or e.published = false))
          or e.meeting_requested = false
      )
    for update of e skip locked
    limit 1;

    if v_event_id is not null then
        return query
        select
            true as delete,
            null::double precision as duration_secs,
            e.event_id,
            null::text[] as hosts,
            m.join_url,
            m.meeting_id,
            m.meeting_provider_id,
            m.password,
            m.provider_meeting_id,
            null::boolean as requires_password,
            null::uuid as session_id,
            null::timestamptz as starts_at,
            null::text as timezone,
            null::text as topic
        from event e
        left join meeting m on m.event_id = e.event_id
        where e.event_id = v_event_id;
        return;
    end if;

    -- Case 4: Session needing delete (parent event inactive or meeting disabled)
    select s.session_id into v_session_id
    from session s
    join event e on e.event_id = s.event_id
    left join meeting m on m.session_id = s.session_id
    where s.meeting_in_sync = false
      and (
        (s.meeting_requested = true and (e.deleted = true or e.canceled = true or e.published = false))
        or s.meeting_requested = false
      )
    for update of s skip locked
    limit 1;

    if v_session_id is not null then
        return query
        select
            true as delete,
            null::double precision as duration_secs,
            null::uuid as event_id,
            null::text[] as hosts,
            m.join_url,
            m.meeting_id,
            m.meeting_provider_id,
            m.password,
            m.provider_meeting_id,
            null::boolean as requires_password,
            s.session_id,
            null::timestamptz as starts_at,
            null::text as timezone,
            null::text as topic
        from session s
        left join meeting m on m.session_id = s.session_id
        where s.session_id = v_session_id;
        return;
    end if;

    -- Case 5: Orphan meetings (no event_id or session_id)
    return query
    select
        true as delete,
        null::double precision as duration_secs,
        null::uuid as event_id,
        null::text[] as hosts,
        m.join_url,
        m.meeting_id,
        m.meeting_provider_id,
        m.password,
        m.provider_meeting_id,
        null::boolean as requires_password,
        null::uuid as session_id,
        null::timestamptz as starts_at,
        null::text as timezone,
        null::text as topic
    from meeting m
    where m.event_id is null and m.session_id is null
    for update skip locked
    limit 1;
end;
$$ language plpgsql;
