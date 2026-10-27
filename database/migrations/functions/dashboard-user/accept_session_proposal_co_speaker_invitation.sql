-- Accepts a pending co-speaker invitation for a session proposal.
create or replace function accept_session_proposal_co_speaker_invitation(
    p_actor_user_id uuid,
    p_session_proposal_id uuid
)
returns void as $$
begin
    -- Record the co-speaker's acceptance
    perform respond_session_proposal_co_speaker_invitation(
        p_actor_user_id,
        p_session_proposal_id,
        true
    );
end;
$$ language plpgsql;
