-- Adds a new session proposal for a user.
create or replace function add_session_proposal(
    p_user_id uuid,
    p_session_proposal jsonb
)
returns uuid as $$
    insert into session_proposal (
        description,
        duration,
        session_proposal_level_id,
        title,
        user_id,
        co_speaker_user_id
    ) values (
        p_session_proposal->>'description',
        make_interval(mins => (p_session_proposal->>'duration_minutes')::int),
        p_session_proposal->>'session_proposal_level_id',
        p_session_proposal->>'title',
        p_user_id,
        nullif(p_session_proposal->>'co_speaker_user_id', '')::uuid
    )
    returning session_proposal_id;
$$ language sql;
