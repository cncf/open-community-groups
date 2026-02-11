-- Accepts a pending co-speaker invitation for a session proposal.
create or replace function accept_session_proposal_co_speaker_invitation(
    p_user_id uuid,
    p_session_proposal_id uuid
)
returns void as $$
begin
    -- Ensure this proposal is currently assigned to the co-speaker
    perform 1
    from session_proposal sp
    where sp.session_proposal_id = p_session_proposal_id
    and sp.co_speaker_user_id = p_user_id;

    if not found then
        raise exception 'session proposal invitation not found';
    end if;

    -- Ensure invitation is still pending before accepting
    perform 1
    from session_proposal sp
    where sp.session_proposal_id = p_session_proposal_id
    and sp.co_speaker_user_id = p_user_id
    and sp.session_proposal_status_id = 'pending-co-speaker-response';

    if not found then
        raise exception 'session proposal is not awaiting co-speaker response';
    end if;

    -- Mark proposal as ready for submission after co-speaker acceptance
    update session_proposal set
        session_proposal_status_id = 'ready-for-submission',
        updated_at = current_timestamp
    where session_proposal_id = p_session_proposal_id
    and co_speaker_user_id = p_user_id;
end;
$$ language plpgsql;
