-- Replaces the labels linked to a session.
create or replace function sync_session_labels(
    p_session_id uuid,
    p_event_id uuid,
    p_label_ids uuid[]
)
returns void as $$
begin
    -- Ensure the session belongs to the event before mutating labels
    perform 1
    from session s
    where s.session_id = p_session_id
    and s.event_id = p_event_id;

    -- Reject sessions that belong to another event
    if not found then
        raise exception 'session not found' using errcode = 'OCG01';
    end if;

    -- Validate supplied labels before replacing existing links
    perform validate_event_label_ids(p_event_id, p_label_ids);

    -- Remove the current label links
    delete from session_label
    where session_id = p_session_id;

    -- Insert supplied labels, deduplicating repeated IDs
    insert into session_label (event_label_id, session_id)
    select distinct input_label.event_label_id, p_session_id
    from unnest(p_label_ids) as input_label(event_label_id);
end;
$$ language plpgsql;
