-- Returns submission data needed for notifications.
create or replace function get_cfs_submission_notification_data(
    p_event_id uuid,
    p_cfs_submission_id uuid
)
returns json as $$
    select json_strip_nulls(json_build_object(
        'status_id', cs.status_id,
        'status_name', css.display_name,
        'user_id', sp.user_id,

        'action_required_message', cs.action_required_message
    ))
    from cfs_submission cs
    join session_proposal sp on sp.session_proposal_id = cs.session_proposal_id
    join cfs_submission_status css on css.cfs_submission_status_id = cs.status_id
    where cs.event_id = p_event_id
    and cs.cfs_submission_id = p_cfs_submission_id;
$$ language sql;
