-- Adds a new CFS submission for an event.
create or replace function add_cfs_submission(
    p_alliance_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_session_proposal_id uuid,
    p_label_ids uuid[] default null
)
returns uuid as $$
declare
    v_cfs_ends_at timestamptz;
    v_cfs_enabled boolean;
    v_cfs_starts_at timestamptz;
    v_submission_id uuid;
begin
    -- Fetch event CFS settings
    select e.cfs_ends_at, e.cfs_enabled, e.cfs_starts_at
    into v_cfs_ends_at, v_cfs_enabled, v_cfs_starts_at
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and g.alliance_id = p_alliance_id
    and g.active = true
    and e.canceled = false
    and e.deleted = false
    and e.published = true;

    -- Validate CFS is enabled
    if v_cfs_enabled is distinct from true then
        raise exception 'cfs is not enabled for this event';
    end if;

    -- Validate CFS window is configured
    if v_cfs_starts_at is null or v_cfs_ends_at is null then
        raise exception 'cfs window not configured';
    end if;

    -- Validate CFS is currently open
    if current_timestamp < v_cfs_starts_at or current_timestamp >= v_cfs_ends_at then
        raise exception 'cfs is not open';
    end if;

    -- Validate proposal ownership
    perform 1
    from session_proposal sp
    where sp.session_proposal_id = p_session_proposal_id
    and sp.user_id = p_user_id;

    if not found then
        raise exception 'session proposal not found';
    end if;

    -- Validate proposal can be submitted
    perform 1
    from session_proposal sp
    where sp.session_proposal_id = p_session_proposal_id
    and sp.session_proposal_status_id = 'ready-for-submission';

    if not found then
        raise exception 'session proposal not ready for submission';
    end if;

    -- Validate labels payload
    perform validate_cfs_submission_label_ids(p_event_id, p_label_ids);

    -- Create submission
    insert into cfs_submission (
        event_id,
        session_proposal_id,
        status_id
    ) values (
        p_event_id,
        p_session_proposal_id,
        'not-reviewed'
    )
    returning cfs_submission_id into v_submission_id;

    -- Link labels to submission
    perform sync_cfs_submission_labels(v_submission_id, p_event_id, p_label_ids);

    return v_submission_id;
end;
$$ language plpgsql;
