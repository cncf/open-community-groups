-- validate_event_series_action_event_ids validates event ids for series actions.
create or replace function validate_event_series_action_event_ids(
    p_group_id uuid,
    p_event_ids uuid[],
    p_require_not_canceled boolean default false
)
returns uuid[] as $$
declare
    v_event_ids uuid[] := array(
        select distinct event_id
        from unnest(coalesce(p_event_ids, '{}'::uuid[])) as events(event_id)
        order by event_id
    );
    v_found_events int;
    v_series_count int;
    v_standalone_events int;
begin
    -- Validate event count
    if cardinality(v_event_ids) = 0 then
        raise exception 'event_ids cannot be empty';
    end if;

    -- Validate event state
    select count(*)::int
    into v_found_events
    from event
    where event_id = any(v_event_ids)
    and group_id = p_group_id
    and deleted = false
    and (
        coalesce(p_require_not_canceled, false) = false
        or canceled = false
    );

    if v_found_events <> cardinality(v_event_ids) then
        raise exception 'one or more events were not found or inactive';
    end if;

    -- Validate series membership
    select
        count(distinct event_series_id)::int,
        (count(*) filter (where event_series_id is null))::int
    into
        v_series_count,
        v_standalone_events
    from event
    where event_id = any(v_event_ids)
    and group_id = p_group_id
    and deleted = false
    and (
        coalesce(p_require_not_canceled, false) = false
        or canceled = false
    );

    -- Validate series consistency
    if v_standalone_events > 0 or v_series_count <> 1 then
        raise exception 'events must belong to the same series';
    end if;

    return v_event_ids;
end;
$$ language plpgsql;
