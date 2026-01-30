-- Updates a session proposal for a user.
create or replace function update_session_proposal(
    p_user_id uuid,
    p_session_proposal_id uuid,
    p_session_proposal jsonb
)
returns void as $$
begin
    -- Ensure the session proposal is not linked to an accepted session
    perform 1
    from cfs_submission cs
    join session s on s.cfs_submission_id = cs.cfs_submission_id
    where cs.session_proposal_id = p_session_proposal_id;

    if found then
        raise exception 'session proposal linked to a session';
    end if;

    -- Update the session proposal
    update session_proposal set
        description = p_session_proposal->>'description',
        duration = make_interval(mins => (p_session_proposal->>'duration_minutes')::int),
        session_proposal_level_id = p_session_proposal->>'session_proposal_level_id',
        title = p_session_proposal->>'title',
        co_speaker_user_id = nullif(p_session_proposal->>'co_speaker_user_id', '')::uuid,
        updated_at = current_timestamp
    where session_proposal_id = p_session_proposal_id
    and user_id = p_user_id;

    if not found then
        raise exception 'session proposal not found';
    end if;
end;
$$ language plpgsql;
