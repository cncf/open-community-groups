-- Adds a new session proposal for a user.
create or replace function add_session_proposal(
    p_actor_user_id uuid,
    p_session_proposal jsonb
)
returns uuid as $$
declare
    v_session_proposal_id uuid;
begin
    -- Insert the session proposal
    insert into session_proposal (
        co_speaker_user_id,
        description,
        duration,
        session_proposal_level_id,
        session_proposal_status_id,
        title,
        user_id
    ) values (
        nullif(p_session_proposal->>'co_speaker_user_id', '')::uuid,
        p_session_proposal->>'description',
        make_interval(mins => (p_session_proposal->>'duration_minutes')::int),
        p_session_proposal->>'session_proposal_level_id',
        case
            when nullif(p_session_proposal->>'co_speaker_user_id', '')::uuid is null then 'ready-for-submission'
            else 'pending-co-speaker-response'
        end,
        p_session_proposal->>'title',
        p_actor_user_id
    )
    returning session_proposal_id into v_session_proposal_id;

    -- Track the session proposal creation
    perform insert_audit_log(
        'session_proposal_added',
        p_actor_user_id,
        'session_proposal',
        v_session_proposal_id
    );

    return v_session_proposal_id;
end;
$$ language plpgsql;
