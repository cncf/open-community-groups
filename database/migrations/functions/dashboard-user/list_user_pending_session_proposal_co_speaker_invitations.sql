-- Returns pending co-speaker invitations for a user
create or replace function list_user_pending_session_proposal_co_speaker_invitations(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(row_to_json(invitation)), '[]'::json)
    from (
        select
            sp.session_proposal_id,
            sp.title,

            coalesce(nullif(btrim(speaker.name), ''), speaker.username) as speaker_name,
            extract(epoch from coalesce(sp.updated_at, sp.created_at))::bigint as updated_at
        from session_proposal sp
        join "user" speaker using (user_id)
        where sp.co_speaker_user_id = p_user_id
          and sp.session_proposal_status_id = 'pending-co-speaker-response'
        order by coalesce(sp.updated_at, sp.created_at) desc, sp.title asc, sp.session_proposal_id asc
    ) invitation;
$$ language sql;
