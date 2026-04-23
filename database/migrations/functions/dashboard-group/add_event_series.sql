-- add_event_series adds a linked recurring event series atomically.
create or replace function add_event_series(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_events jsonb,
    p_recurrence jsonb,
    p_cfg_max_participants jsonb default null
)
returns uuid[] as $$
declare
    v_additional_occurrences int := (p_recurrence->>'additional_occurrences')::int;
    v_event jsonb;
    v_event_id uuid;
    v_event_ids uuid[] := '{}';
    v_event_series_id uuid;
    v_first_event jsonb;
    v_pattern text := p_recurrence->>'pattern';
    v_timezone text;
begin
    -- Validate event count
    if jsonb_array_length(p_events) < 2 or jsonb_array_length(p_events) > 13 then
        raise exception 'events must include between 2 and 13 items';
    end if;

    -- Validate additional occurrence count
    if v_additional_occurrences is null or v_additional_occurrences < 1 or v_additional_occurrences > 12 then
        raise exception 'additional_occurrences must be between 1 and 12';
    end if;

    -- Validate recurrence count consistency
    if jsonb_array_length(p_events) <> v_additional_occurrences + 1 then
        raise exception 'events count must match additional_occurrences';
    end if;

    -- Validate recurrence pattern
    if nullif(v_pattern, '') is null or v_pattern not in ('weekly', 'biweekly', 'monthly') then
        raise exception 'unsupported recurrence pattern';
    end if;

    v_first_event := p_events->0;
    v_timezone := v_first_event->>'timezone';

    -- Validate anchor timezone
    if nullif(v_timezone, '') is null then
        raise exception 'recurring events require timezone';
    end if;

    -- Validate anchor start date
    if nullif(v_first_event->>'starts_at', '') is null then
        raise exception 'recurring events require starts_at';
    end if;

    -- Create the series row shared by every generated event.
    insert into event_series (
        group_id,
        recurrence_additional_occurrences,
        recurrence_anchor_starts_at,
        recurrence_pattern,
        timezone,

        created_by
    ) values (
        p_group_id,
        v_additional_occurrences,
        (v_first_event->>'starts_at')::timestamp at time zone v_timezone,
        v_pattern,
        v_timezone,

        p_actor_user_id
    )
    returning event_series_id into v_event_series_id;

    -- Create each event using the existing single-event behavior and then link it.
    for v_event in select jsonb_array_elements(p_events)
    loop
        v_event_id := add_event(
            p_actor_user_id,
            p_group_id,
            v_event,
            p_cfg_max_participants
        );

        update event
        set event_series_id = v_event_series_id
        where event_id = v_event_id;

        v_event_ids := array_append(v_event_ids, v_event_id);
    end loop;

    return v_event_ids;
end;
$$ language plpgsql;
