-- Validates the label IDs assigned to a CFS submission or session.
create or replace function validate_event_label_ids(
    p_event_id uuid,
    p_label_ids uuid[]
)
returns void as $$
begin
    -- Enforce the maximum number of labels assigned to one item
    if coalesce(array_length(p_label_ids, 1), 0) > 10 then
        raise exception 'too many labels' using errcode = 'OCG01';
    end if;

    -- Ensure all supplied labels belong to the event
    if exists (
        select 1
        from unnest(p_label_ids) as input_label(event_label_id)
        where not exists (
            select 1
            from event_label el
            where el.event_label_id = input_label.event_label_id
            and el.event_id = p_event_id
        )
    ) then
        raise exception 'invalid event labels' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;
