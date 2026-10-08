-- Returns the JSON payload for the given event labels ordered by name.
create or replace function event_labels_json(p_event_label_ids uuid[])
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'color', el.color,
                'event_label_id', el.event_label_id,
                'name', el.name
            )
            order by el.name asc, el.event_label_id asc
        ),
        '[]'::json
    )
    from event_label el
    where el.event_label_id = any(p_event_label_ids);
$$ language sql;
