-- Returns user session proposals with submission status for a specific event.
create or replace function list_user_session_proposals_for_cfs_event(
    p_user_id uuid,
    p_event_id uuid
)
returns json as $$
    select coalesce(
        json_agg(
            json_strip_nulls(json_build_object(
                'created_at', extract(epoch from sp.created_at)::bigint,
                'description', sp.description,
                'duration_minutes', floor(extract(epoch from sp.duration) / 60)::int,
                'session_proposal_id', sp.session_proposal_id,
                'session_proposal_level_id', sp.session_proposal_level_id,
                'session_proposal_level_name', spl.display_name,
                'title', sp.title,

                'co_speaker', case
                    when co.user_id is null then null
                    else json_strip_nulls(json_build_object(
                        'user_id', co.user_id,
                        'username', co.username,

                        'company', co.company,
                        'name', co.name,
                        'photo_url', co.photo_url,
                        'title', co.title
                    ))
                end,
                'submission_status_id', cs.status_id,
                'submission_status_name', css.display_name,
                'updated_at', extract(epoch from sp.updated_at)::bigint,

                'is_submitted', cs.cfs_submission_id is not null
            ))
            order by sp.title asc, sp.session_proposal_id asc
        ),
        '[]'::json
    )
    from session_proposal sp
    join session_proposal_level spl using (session_proposal_level_id)
    left join cfs_submission cs
        on cs.session_proposal_id = sp.session_proposal_id
        and cs.event_id = p_event_id
    left join cfs_submission_status css
        on css.cfs_submission_status_id = cs.status_id
    left join "user" co
        on co.user_id = sp.co_speaker_user_id
    where sp.user_id = p_user_id;
$$ language sql;
