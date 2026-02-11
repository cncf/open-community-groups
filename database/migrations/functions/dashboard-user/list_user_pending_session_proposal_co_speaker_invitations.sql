-- Returns pending co-speaker invitations for a user
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
                    else json_strip_nulls(json_build_object(
                        'user_id', co.user_id,
                        'username', co.username,

                        'company', co.company,
                        'name', co.name,
                        'photo_url', co.photo_url,
                        'title', co.title
                    ))
                end as co_speaker,
                null::uuid as linked_session_id,
                extract(epoch from sp.updated_at)::bigint as updated_at,

                extract(epoch from sp.created_at)::bigint as created_at,
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
