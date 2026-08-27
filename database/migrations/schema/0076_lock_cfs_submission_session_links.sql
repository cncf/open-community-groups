-- Serializes CFS submission review with session linking.

create or replace function check_session_cfs_submission_approved()
returns trigger as $$
declare
    v_event_id uuid;
    v_status_id text;
begin
    -- Skip validation when no submission is linked
    if new.cfs_submission_id is null then
        return new;
    end if;

    -- Lock and load the submission state used by the session link
    select
        cs.event_id,
        cs.status_id
    into
        v_event_id,
        v_status_id
    from cfs_submission cs
    where cs.cfs_submission_id = new.cfs_submission_id
    for share;

    -- Reject links to missing submissions
    if v_event_id is null then
        raise exception 'cfs submission not found';
    end if;

    -- Reject links to submissions for another event
    if v_event_id <> new.event_id then
        raise exception 'cfs submission does not belong to the session event';
    end if;

    -- Reject links to submissions outside the approved state
    if v_status_id <> 'approved' then
        raise exception 'cfs submission must be approved';
    end if;

    -- Return the validated session row
    return new;
end;
$$ language plpgsql;
