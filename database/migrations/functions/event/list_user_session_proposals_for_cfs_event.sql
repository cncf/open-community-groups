-- Returns user session proposals with submission status for a specific event.
create or replace function list_user_session_proposals_for_cfs_event(
    p_user_id uuid,
    p_event_id uuid
)
returns json as $$
    -- Build user proposals payload with submission status for the event
    select coalesce(
        json_agg(
            jsonb_strip_nulls(session_proposal_json(sp) || jsonb_build_object(
                -- Include proposal creation time and status
                'created_at', epoch_seconds(sp.created_at),
                'session_proposal_status_id', sp.session_proposal_status_id,
                'status_name', sps.display_name,

                -- Include submission status, update time and derived flags
                'submission_status_id', cs.status_id,
                'submission_status_name', css.display_name,
                'updated_at', epoch_seconds(sp.updated_at),

                'is_submitted', cs.cfs_submission_id is not null
            ))
            order by sp.title asc, sp.session_proposal_id asc
        ),
        '[]'::json
    )
    from session_proposal sp
    join session_proposal_status sps on sps.session_proposal_status_id = sp.session_proposal_status_id
    left join cfs_submission cs
        on cs.session_proposal_id = sp.session_proposal_id
        and cs.event_id = p_event_id
    left join cfs_submission_status css
        on css.cfs_submission_status_id = cs.status_id
    where sp.user_id = p_user_id
    and sp.session_proposal_status_id = 'ready-for-submission';
$$ language sql stable;
