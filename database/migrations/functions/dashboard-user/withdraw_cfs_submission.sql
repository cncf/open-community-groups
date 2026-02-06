-- Marks a CFS submission as withdrawn.
create or replace function withdraw_cfs_submission(
    p_user_id uuid,
    p_cfs_submission_id uuid
)
returns void as $$
begin
    -- Mark the submission as withdrawn
    update cfs_submission cs set
        status_id = 'withdrawn',
        updated_at = current_timestamp
    from session_proposal sp
    where cs.cfs_submission_id = p_cfs_submission_id
    and cs.session_proposal_id = sp.session_proposal_id
    and sp.user_id = p_user_id
    and cs.status_id in ('information-requested', 'not-reviewed')
    and not exists (
        select 1
        from session s
        where s.cfs_submission_id = cs.cfs_submission_id
    );

    -- Ensure submission exists and can be withdrawn
    if not found then
        raise exception 'submission not found or cannot be withdrawn';
    end if;
end;
$$ language plpgsql;
