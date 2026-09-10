-- Returns pending co-speaker invitations for a user.
create or replace function list_user_pending_session_proposal_co_speaker_invitations(p_user_id uuid)
returns json as $$
    with
        -- Gather pending co-speaker invitations
        invitations as (
            select
                sp.description,
                sp.session_proposal_id,
                sp.session_proposal_level_id,
                spl.display_name as session_proposal_level_name,
                sp.session_proposal_status_id as session_proposal_status_id,
                coalesce(nullif(btrim(speaker.name), ''), speaker.username) as speaker_name,
                sps.display_name as status_name,
                sp.title,

                case
                    when co.user_id is null then null
                    else public_user_summary(co)
                end as co_speaker,
                null::uuid as linked_session_id,
                speaker.photo_url as speaker_photo_url,
                epoch_seconds(sp.updated_at) as updated_at,

                epoch_seconds(sp.created_at) as created_at,
                floor(extract(epoch from sp.duration) / 60)::int as duration_minutes,
                false as has_submissions
            from session_proposal sp
            join "user" speaker using (user_id)
            join session_proposal_level spl using (session_proposal_level_id)
            join session_proposal_status sps on sps.session_proposal_status_id = sp.session_proposal_status_id
            left join "user" co on co.user_id = sp.co_speaker_user_id
            where sp.co_speaker_user_id = p_user_id
              and sp.session_proposal_status_id = 'pending-co-speaker-response'
            order by coalesce(sp.updated_at, sp.created_at) desc, sp.title asc, sp.session_proposal_id asc
        )
    select coalesce(json_agg(row_to_json(invitations)), '[]'::json)
    from invitations;
$$ language sql;
