-- Maintains event capacity from ticket type seats after locking affected events in stable order.
create or replace function sync_event_capacity_from_ticket_types()
returns trigger as $$
declare
    v_event_id uuid;
    v_event_ids uuid[];
begin
    -- Resolve events that received new tiers
    if tg_op = 'INSERT' then
        select array_agg(distinct ntt.event_id order by ntt.event_id)
        into v_event_ids
        from new_ticket_types ntt;

    -- Resolve events that lost tiers
    elsif tg_op = 'DELETE' then
        select array_agg(distinct ott.event_id order by ott.event_id)
        into v_event_ids
        from old_ticket_types ott;

    -- Resolve events touched on either side of an update
    else
        select array_agg(distinct ae.event_id order by ae.event_id)
        into v_event_ids
        from (
            select ntt.event_id
            from new_ticket_types ntt

            union all

            select ott.event_id
            from old_ticket_types ott
        ) ae;
    end if;

    -- Recompute capacity for each affected event in event_id order
    foreach v_event_id in array coalesce(v_event_ids, array[]::uuid[]) loop
        -- Lock before aggregating so a waiter sees concurrent committed tier writes
        perform 1
        from event
        where event_id = v_event_id
        for no key update;

        -- Persist the summed seats as the event capacity
        update event e
        set capacity = coalesce((
            select sum(ett.seats_total)::int
            from event_ticket_type ett
            where ett.event_id = v_event_id
        ), 0)
        where e.event_id = v_event_id;
    end loop;

    -- Statement triggers ignore the returned row
    return null;
end;
$$ language plpgsql;
