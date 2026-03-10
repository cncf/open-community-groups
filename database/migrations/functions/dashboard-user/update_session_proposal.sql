-- Updates a session proposal for a user.
create or replace function update_session_proposal(
    p_user_id uuid,
    p_session_proposal_id uuid,
    p_session_proposal jsonb
)
returns void as $$
declare
    v_current_co_speaker_user_id uuid;
    v_new_co_speaker_user_id uuid;
begin
    -- Ensure the session proposal belongs to the user and load current co-speaker
    select sp.co_speaker_user_id
    into v_current_co_speaker_user_id
    from session_proposal sp
    where sp.session_proposal_id = p_session_proposal_id
    and sp.user_id = p_user_id;

    if not found then
        raise exception 'session proposal not found';
    end if;

    -- Parse incoming co-speaker
    v_new_co_speaker_user_id := nullif(p_session_proposal->>'co_speaker_user_id', '')::uuid;

    -- Ensure the session proposal is not linked to an accepted session
    perform 1
    from cfs_submission cs
    join session s on s.cfs_submission_id = cs.cfs_submission_id
    where cs.session_proposal_id = p_session_proposal_id;

    if found then
        raise exception 'session proposal linked to a session';
    end if;

    -- Ensure proposals with submissions keep the same co-speaker
    if v_new_co_speaker_user_id is distinct from v_current_co_speaker_user_id then
        perform 1
        from cfs_submission cs
        where cs.session_proposal_id = p_session_proposal_id;

        if found then
            raise exception 'session proposal with submissions cannot change co-speaker';
        end if;
    end if;

    -- Update the session proposal
    update session_proposal set
        co_speaker_user_id = v_new_co_speaker_user_id,
        description = p_session_proposal->>'description',
        duration = make_interval(mins => (p_session_proposal->>'duration_minutes')::int),
        session_proposal_level_id = p_session_proposal->>'session_proposal_level_id',
        session_proposal_status_id = case
            when v_new_co_speaker_user_id is distinct from v_current_co_speaker_user_id then
                case
                    when v_new_co_speaker_user_id is null then 'ready-for-submission'
                    else 'pending-co-speaker-response'
                end
            else session_proposal_status_id
        end,
        title = p_session_proposal->>'title',
        updated_at = current_timestamp
    where session_proposal_id = p_session_proposal_id
    and user_id = p_user_id;

    if not found then
        raise exception 'session proposal not found';
    end if;
end;
$$ language plpgsql;
