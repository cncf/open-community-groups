-- Locks a group and its event mutation targets in canonical order.
create or replace function lock_group_events(
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
    v_locked_event_count integer;
begin
    -- Reject empty mutation scopes
    if cardinality(v_event_ids) = 0 then
        raise exception 'event_ids cannot be empty';
    end if;

    -- Lock the owning group before any target event
    perform 1
    from "group" g
    where g.group_id = p_group_id
    and g.deleted = false
    for update;

    -- Reject missing or inactive owning groups
    if not found then
        raise exception 'group not found or inactive';
    end if;

    -- Lock every non-deleted target in canonical order
    perform 1
    from event e
    where e.event_id = any(v_event_ids)
    and e.group_id = p_group_id
    and e.deleted = false
    order by e.event_id
    for update;

    get diagnostics v_locked_event_count = row_count;

    -- Reject stale or cross-group scopes after locking available targets
    if v_locked_event_count <> cardinality(v_event_ids) then
        raise exception 'one or more events were not found or inactive';
    end if;
end;
$$ language plpgsql;
