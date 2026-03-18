-- Promotes waitlisted users into attendee seats for an event.
create or replace function promote_event_waitlist(
    p_event_id uuid,
    p_slots int default null
)
returns json as $$
declare
    v_attendee_count int;
    v_available_slots int;
    v_capacity int;
    v_promoted_user_ids uuid[] := '{}';
    v_waitlist_entry record;
    v_waitlist_count int;
begin
    -- Ignore invalid capped promotion requests
    if p_slots is not null and p_slots <= 0 then
        return '[]'::json;
    end if;

    -- Lock event row and load capacity configuration
    select e.capacity
    into v_capacity
    from event e
    where e.event_id = p_event_id
    for update of e;

    if not found then
        return '[]'::json;
    end if;

    -- Compute how many seats can be filled from the waitlist
    if v_capacity is null then
        select count(*) into v_waitlist_count
        from event_waitlist
        where event_id = p_event_id;

        v_available_slots := v_waitlist_count;
    else
        select count(*) into v_attendee_count
        from event_attendee
        where event_id = p_event_id;

        v_available_slots := greatest(v_capacity - v_attendee_count, 0);
    end if;

    if p_slots is not null then
        v_available_slots := least(v_available_slots, p_slots);
    end if;

    if v_available_slots <= 0 then
        return '[]'::json;
    end if;

    -- Promote the oldest waitlisted users first
    for v_waitlist_entry in
        select ew.user_id
        from event_waitlist ew
        where ew.event_id = p_event_id
        order by ew.created_at asc, ew.user_id asc
        limit v_available_slots
    loop
        -- Lock the event-user pair before moving it between attendance tables
        perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(v_waitlist_entry.user_id::text));

        -- Remove the waitlist row first so cross-table exclusivity checks allow the attendee insert
        delete from event_waitlist
        where event_id = p_event_id
        and user_id = v_waitlist_entry.user_id;

        -- Skip entries already removed by a concurrent promotion attempt
        if not found then
            continue;
        end if;

        -- Insert the promoted user as an attendee (tolerate concurrent duplicate inserts)
        insert into event_attendee (event_id, user_id)
        values (p_event_id, v_waitlist_entry.user_id)
        on conflict (event_id, user_id) do nothing;

        -- Record only users successfully moved into attendees during this execution
        if found then
            v_promoted_user_ids := array_append(v_promoted_user_ids, v_waitlist_entry.user_id);
        end if;
    end loop;

    return to_json(coalesce(v_promoted_user_ids, '{}'::uuid[]));
end;
$$ language plpgsql;
