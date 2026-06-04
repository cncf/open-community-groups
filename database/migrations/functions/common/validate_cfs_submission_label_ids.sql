-- Validates CFS submission label IDs for an event.
create or replace function validate_cfs_submission_label_ids(
    p_event_id uuid,
    p_label_ids uuid[]
)
returns void as $$
begin
    -- Enforce the maximum number of labels per submission
    if coalesce(array_length(p_label_ids, 1), 0) > 10 then
        raise exception 'too many submission labels';
    end if;

    -- Ensure all supplied labels belong to the event
    if p_label_ids is not null then
        perform 1
        from unnest(p_label_ids) as input_label(event_cfs_label_id)
        where not exists (
            select 1
            from event_cfs_label ecl
            where ecl.event_cfs_label_id = input_label.event_cfs_label_id
            and ecl.event_id = p_event_id
        );

        if found then
            raise exception 'invalid event CFS labels';
        end if;
    end if;
end;
$$ language plpgsql;
