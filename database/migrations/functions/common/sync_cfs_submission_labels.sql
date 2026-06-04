-- Replaces the labels linked to a CFS submission.
create or replace function sync_cfs_submission_labels(
    p_cfs_submission_id uuid,
    p_event_id uuid,
    p_label_ids uuid[]
)
returns void as $$
begin
    -- Ensure the submission belongs to the event before mutating labels
    perform 1
    from cfs_submission cs
    where cs.cfs_submission_id = p_cfs_submission_id
    and cs.event_id = p_event_id;

    if not found then
        raise exception 'submission not found';
    end if;

    -- Validate supplied labels before replacing existing links
    perform validate_cfs_submission_label_ids(p_event_id, p_label_ids);

    -- Remove labels omitted from the payload
    delete from cfs_submission_label
    where cfs_submission_id = p_cfs_submission_id;

    -- Insert supplied labels, deduplicating repeated IDs
    if p_label_ids is not null then
        insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id)
        select p_cfs_submission_id, input_label.event_cfs_label_id
        from unnest(p_label_ids) as input_label(event_cfs_label_id)
        group by input_label.event_cfs_label_id;
    end if;
end;
$$ language plpgsql;
