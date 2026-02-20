-- Returns labels available for an event.
create or replace function list_event_cfs_labels(p_event_id uuid)
returns json as $$
    -- Build labels payload ordered by label name
    select coalesce(
        json_agg(
            json_build_object(
                'color', ecl.color,
                'event_cfs_label_id', ecl.event_cfs_label_id,
                'name', ecl.name
            )
            order by ecl.name asc, ecl.event_cfs_label_id asc
        ),
        '[]'::json
    )
    from event_cfs_label ecl
    where ecl.event_id = p_event_id;
$$ language sql;
