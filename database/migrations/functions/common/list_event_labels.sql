-- Returns labels available for an event.
create or replace function list_event_labels(p_event_id uuid)
returns json as $$
    select event_labels_json(
        array(
            select el.event_label_id
            from event_label el
            where el.event_id = p_event_id
        )
    );
$$ language sql;
