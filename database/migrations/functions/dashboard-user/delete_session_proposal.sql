-- Deletes a session proposal for a user.
create or replace function delete_session_proposal(
    p_user_id uuid,
    p_session_proposal_id uuid
)
returns void as $$
begin
    -- Do not allow deletion if there are associated submissions
    perform 1
    from cfs_submission cs
    where cs.session_proposal_id = p_session_proposal_id;

    if found then
        raise exception 'session proposal has submissions';
    end if;

    -- Proceed to delete the session proposal
    delete from session_proposal
    where session_proposal_id = p_session_proposal_id
    and user_id = p_user_id;

    if not found then
        raise exception 'session proposal not found';
    end if;
end;
$$ language plpgsql;
