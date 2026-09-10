-- Maintains event capacity from ticket type seats after locking affected events in stable order.
create or replace function sync_event_capacity_from_ticket_types()
returns trigger as $$
declare
    v_event_id uuid;
begin
    -- Recompute capacity for events that received new tiers
    if tg_op = 'INSERT' then
        for v_event_id in
            select ntt.event_id
            from new_ticket_types ntt
            group by ntt.event_id
            order by ntt.event_id
        loop
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

    -- Recompute capacity for events that lost tiers
    elsif tg_op = 'DELETE' then
        for v_event_id in
            select ott.event_id
            from old_ticket_types ott
            group by ott.event_id
            order by ott.event_id
        loop
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

    -- Recompute capacity for events touched on either side of an update
    else
        for v_event_id in
            with affected_events as (
                select ntt.event_id
                from new_ticket_types ntt

                union all

                select ott.event_id
                from old_ticket_types ott
            )
            select ae.event_id
            from affected_events ae
            group by ae.event_id
            order by ae.event_id
        loop
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
    end if;

    -- Statement triggers ignore the returned row
    return null;
end;
$$ language plpgsql;
