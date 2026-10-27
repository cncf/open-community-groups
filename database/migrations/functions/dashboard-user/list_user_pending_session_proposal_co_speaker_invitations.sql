-- Returns pending co-speaker invitations for a user.
create or replace function list_user_pending_session_proposal_co_speaker_invitations(p_user_id uuid)
returns json as $$
    with
        -- Gather pending co-speaker invitations
        invitations as (
            select
                session_proposal_json(sp) || jsonb_build_object(
                    'session_proposal_status_id', sp.session_proposal_status_id,
                    'speaker_name', coalesce(nullif(btrim(speaker.name), ''), speaker.username),
                    'status_name', sps.display_name,

                    'linked_session_id', null::uuid,
                    'speaker_photo_url', speaker.photo_url,
                    'updated_at', epoch_seconds(sp.updated_at),

                    'created_at', epoch_seconds(sp.created_at),
                    'has_submissions', false
                ) as invitation
            from session_proposal sp
            join "user" speaker using (user_id)
            join session_proposal_status sps on sps.session_proposal_status_id = sp.session_proposal_status_id
            where sp.co_speaker_user_id = p_user_id
              and sp.session_proposal_status_id = 'pending-co-speaker-response'
            order by coalesce(sp.updated_at, sp.created_at) desc, sp.title asc, sp.session_proposal_id asc
        )
    select coalesce(json_agg(invitation), '[]'::json)
    from invitations;
$$ language sql stable;
