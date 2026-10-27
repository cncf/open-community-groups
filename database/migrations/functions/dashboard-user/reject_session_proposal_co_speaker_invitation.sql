-- Rejects a pending co-speaker invitation for a session proposal.
create or replace function reject_session_proposal_co_speaker_invitation(
    p_actor_user_id uuid,
    p_session_proposal_id uuid
)
returns void as $$
begin
    -- Record the co-speaker's rejection
    perform respond_session_proposal_co_speaker_invitation(
        p_actor_user_id,
        p_session_proposal_id,
        false
    );
end;
$$ language plpgsql;
