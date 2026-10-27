-- Deletes a session proposal for a user.
create or replace function delete_session_proposal(
    p_actor_user_id uuid,
    p_session_proposal_id uuid
)
returns void as $$
declare
    v_title text;
begin
    -- Lock the user's session proposal and snapshot its title for the audit row
    select sp.title
    into v_title
    from session_proposal sp
    where sp.session_proposal_id = p_session_proposal_id
    and sp.user_id = p_actor_user_id
    for update of sp;

    -- Reject proposals outside the user's ownership
    if not found then
        raise exception 'session proposal not found' using errcode = 'OCG01';
    end if;

    -- Do not allow deletion if there are associated submissions
    perform 1
    from cfs_submission cs
    where cs.session_proposal_id = p_session_proposal_id;

    -- Preserve proposals already submitted to an event
    if found then
        raise exception 'session proposal has submissions' using errcode = 'OCG01';
    end if;

    -- Proceed to delete the session proposal
    delete from session_proposal
    where session_proposal_id = p_session_proposal_id
    and user_id = p_actor_user_id;

    -- Track the deleted session proposal with its title
    perform insert_audit_log(
        'session_proposal_deleted',
        p_actor_user_id,
        'session_proposal',
        p_session_proposal_id,
        p_details => jsonb_build_object('title', v_title)
    );
end;
$$ language plpgsql;
