-- validate_event_cfs_labels_payload validates event CFS labels.
create or replace function validate_event_cfs_labels_payload(p_cfs_labels jsonb)
returns void as $$
begin
    -- Validate the overall CFS labels payload shape
    if p_cfs_labels is null then
        return;
    end if;

    -- Enforce the maximum number of labels accepted in one payload
    if jsonb_array_length(p_cfs_labels) > 200 then
        raise exception 'too many cfs labels';
    end if;

    -- Reject duplicate non-empty label names within the payload
    if exists (
        select 1
        from (
            select nullif(cfs_label->>'name', '') as cfs_label_name
            from jsonb_array_elements(p_cfs_labels) as cfs_label
        ) cfs_labels
        where cfs_labels.cfs_label_name is not null
        group by cfs_labels.cfs_label_name
        having count(*) > 1
    ) then
        raise exception 'duplicate cfs label names';
    end if;
end;
$$ language plpgsql;
