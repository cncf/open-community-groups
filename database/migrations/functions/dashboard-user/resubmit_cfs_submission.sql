-- Resubmits a CFS submission after information is requested.
create or replace function resubmit_cfs_submission(
    p_user_id uuid,
    p_cfs_submission_id uuid
)
returns void as $$
begin
    -- Reset submission for review
    update cfs_submission cs set
        action_required_message = null,
        status_id = 'not-reviewed',
        updated_at = current_timestamp
    from session_proposal sp
    where cs.cfs_submission_id = p_cfs_submission_id
    and cs.session_proposal_id = sp.session_proposal_id
    and sp.user_id = p_user_id
    and cs.status_id = 'information-requested'
    and not exists (
        select 1
        from session s
        where s.cfs_submission_id = cs.cfs_submission_id
    );

    -- Ensure submission exists and can be resubmitted
    if not found then
        raise exception 'submission not found or cannot be resubmitted';
    end if;
end;
$$ language plpgsql;
