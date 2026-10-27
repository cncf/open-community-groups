-- Records the invited co-speaker's response to a pending session proposal
-- invitation: acceptance makes the proposal ready for submission, rejection
-- marks it declined by the co-speaker.
create or replace function respond_session_proposal_co_speaker_invitation(
    p_actor_user_id uuid,
    p_session_proposal_id uuid,
    p_accepted boolean
)
returns void as $$
begin
    -- Ensure this proposal is currently assigned to the co-speaker
    perform 1
    from session_proposal sp
    where sp.session_proposal_id = p_session_proposal_id
    and sp.co_speaker_user_id = p_actor_user_id;

    -- Reject users who are not the invited co-speaker
    if not found then
        raise exception 'session proposal invitation not found' using errcode = 'OCG01';
    end if;

    -- Record the response, guarding on the pending status to avoid racing a
    -- concurrent response
    update session_proposal set
        session_proposal_status_id = case
            -- Make accepted proposals ready for submission
            when p_accepted then 'ready-for-submission'
            -- Mark rejected proposals as declined by the co-speaker
            else 'declined-by-co-speaker'
        end,
        updated_at = current_timestamp
    where session_proposal_id = p_session_proposal_id
    and co_speaker_user_id = p_actor_user_id
    and session_proposal_status_id = 'pending-co-speaker-response';

    -- Reject responses to proposals no longer awaiting the co-speaker
    if not found then
        raise exception 'session proposal is not awaiting co-speaker response' using errcode = 'OCG01';
    end if;

    -- Track the response
    perform insert_audit_log(
        case
            -- Audit an accepted invitation
            when p_accepted then 'session_proposal_co_speaker_invitation_accepted'
            -- Audit a rejected invitation
            else 'session_proposal_co_speaker_invitation_rejected'
        end,
        p_actor_user_id,
        'session_proposal',
        p_session_proposal_id
    );
end;
$$ language plpgsql;
