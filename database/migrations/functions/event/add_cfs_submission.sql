-- Adds a new CFS submission for an event.
create or replace function add_cfs_submission(
    p_user_id uuid,
    p_event_id uuid,
    p_session_proposal_id uuid
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
    where e.event_id = p_event_id
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

    return v_submission_id;
end;
$$ language plpgsql;
