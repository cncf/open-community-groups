-- Synchronizes the labels of an event with the supplied payload. The caller
-- validates the payload and locks the event.
create or replace function sync_event_labels(
    p_event_id uuid,
    p_labels jsonb
)
returns void as $$
declare
    v_label jsonb;
    v_label_ids uuid[];
begin
    -- Require a labels payload from callers
    if p_labels is null then
        raise exception 'labels payload is required';
    end if;

    -- Collect the supplied label identifiers
    v_label_ids := array(
        select (label->>'event_label_id')::uuid
        from jsonb_array_elements(p_labels) as label
    );

    -- Reject labels owned by another event
    if exists (
        select 1
        from event_label el
        where el.event_label_id = any(v_label_ids)
        and el.event_id <> p_event_id
    ) then
        raise exception 'event label not found for event' using errcode = 'OCG01';
    end if;

    -- Reject existing labels that are no longer stored for the event
    if exists (
        select 1
        from jsonb_array_elements(p_labels) as label
        where coalesce((label->>'is_new')::boolean, false) = false
        and not exists (
            select 1
            from event_label el
            where el.event_label_id = (label->>'event_label_id')::uuid
            and el.event_id = p_event_id
        )
    ) then
        raise exception 'event label not found for event' using errcode = 'OCG01';
    end if;

    -- Defer name uniqueness so labels can swap names
    set constraints event_label_event_id_name_key deferred;

    -- Remove labels omitted from the payload, unlinking them everywhere
    delete from event_label
    where event_id = p_event_id
    and not (event_label_id = any(v_label_ids));

    -- Upsert the supplied labels
    for v_label in select jsonb_array_elements(p_labels)
    loop
        -- Store the label, updating it only when it belongs to this event
        insert into event_label (
            event_label_id,
            color,
            event_id,
            name
        ) values (
            (v_label->>'event_label_id')::uuid,
            v_label->>'color',
            p_event_id,
            btrim(v_label->>'name')
        )
        on conflict (event_label_id) do update set
            color = excluded.color,
            name = excluded.name
        where event_label.event_id = p_event_id;

        -- Reject labels claimed by another event in the meantime
        if not found then
            raise exception 'event label not found for event' using errcode = 'OCG01';
        end if;
    end loop;

    -- Check name uniqueness for the final label set
    begin
        set constraints event_label_event_id_name_key immediate;
    exception
        -- Translate duplicate final names
        when unique_violation then
            raise exception 'duplicate label names' using errcode = 'OCG01';
    end;
end;
$$ language plpgsql;
