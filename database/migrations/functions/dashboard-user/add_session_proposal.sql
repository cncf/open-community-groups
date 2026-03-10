-- Adds a new session proposal for a user.
create or replace function add_session_proposal(
    p_user_id uuid,
    p_session_proposal jsonb
)
returns uuid as $$
declare
    v_co_speaker_user_id uuid;
begin
    -- Parse optional co-speaker from the payload
    v_co_speaker_user_id := nullif(p_session_proposal->>'co_speaker_user_id', '')::uuid;

    -- Prevent speakers from inviting themselves as co-speakers
    if v_co_speaker_user_id = p_user_id then
        raise exception 'session proposal co-speaker cannot be the speaker';
    end if;

    -- Insert the new proposal with the right initial status
    insert into session_proposal (
        co_speaker_user_id,
        description,
        duration,
        session_proposal_level_id,
        session_proposal_status_id,
        title,
        user_id
    ) values (
        v_co_speaker_user_id,
        p_session_proposal->>'description',
        make_interval(mins => (p_session_proposal->>'duration_minutes')::int),
        p_session_proposal->>'session_proposal_level_id',
        case
            when v_co_speaker_user_id is null then 'ready-for-submission'
            else 'pending-co-speaker-response'
        end,
        p_session_proposal->>'title',
        p_user_id
    )
    returning session_proposal_id;
end;
$$ language plpgsql;
