-- Locks active events before cancellation context and recipients are loaded.
create or replace function lock_events_for_cancellation(
    p_group_id uuid,
    p_event_ids uuid[]
)
returns void as $$
declare
    v_event_ids uuid[] := array(
        select distinct events.event_id
        from unnest(coalesce(p_event_ids, '{}'::uuid[])) as events(event_id)
        where events.event_id is not null
        order by events.event_id
    );
    v_locked_event_count int;
begin
    -- Reject empty cancellation scopes
    if cardinality(v_event_ids) = 0 then
        raise exception 'event_ids cannot be empty';
    end if;

    -- Lock every active target in canonical order to serialize attendance changes
    perform 1
    from event e
    where e.event_id = any(v_event_ids)
    and e.group_id = p_group_id
    and e.canceled = false
    and e.deleted = false
    and (
        coalesce(e.ends_at, e.starts_at) is null
        or coalesce(e.ends_at, e.starts_at) >= current_timestamp
    )
    order by e.event_id
    for update;

    get diagnostics v_locked_event_count = row_count;

    -- Reject stale or cross-group scopes after acquiring all available locks
    if v_locked_event_count <> cardinality(v_event_ids) then
        raise exception 'one or more events were not found or inactive';
    end if;
end;
$$ language plpgsql;
