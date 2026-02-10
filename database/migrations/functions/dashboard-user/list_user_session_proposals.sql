-- Returns paginated session proposals for a user.
create or replace function list_user_session_proposals(p_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse pagination filters
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value
        ),
        -- Collect submission counts and linked sessions
        session_proposal_links as (
            select
                sp.session_proposal_id,
                count(cs.cfs_submission_id)::int as submission_count,
                min(s.session_id::text) as linked_session_id
            from session_proposal sp
            left join cfs_submission cs on cs.session_proposal_id = sp.session_proposal_id
            left join session s on s.cfs_submission_id = cs.cfs_submission_id
            where sp.user_id = p_user_id
            group by sp.session_proposal_id
        ),
        -- Gather paginated session proposals
        session_proposals as (
            select
                sp.description,
                sp.session_proposal_id,
                sp.session_proposal_level_id,
                spl.display_name as session_proposal_level_name,
                sp.session_proposal_status_id as session_proposal_status_id,
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
                pl.linked_session_id,

                extract(epoch from sp.created_at)::bigint as created_at,
                floor(extract(epoch from sp.duration) / 60)::int as duration_minutes,
                (pl.submission_count > 0) as has_submissions,
                extract(epoch from sp.updated_at)::bigint as updated_at
            from session_proposal sp
            join session_proposal_level spl using (session_proposal_level_id)
            join session_proposal_status sps
                on sps.session_proposal_status_id = sp.session_proposal_status_id
            left join session_proposal_links pl on pl.session_proposal_id = sp.session_proposal_id
            left join "user" co on co.user_id = sp.co_speaker_user_id
            where sp.user_id = p_user_id
            order by coalesce(sp.updated_at, sp.created_at) desc, sp.title asc, sp.session_proposal_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count total session proposals
        totals as (
            select count(*)::int as total
            from session_proposal sp
            where sp.user_id = p_user_id
        ),
        -- Aggregate session proposals to JSON
        session_proposals_json as (
            select coalesce(json_agg(row_to_json(session_proposals)), '[]'::json) as session_proposals
            from session_proposals
        )
    select json_build_object(
        'session_proposals', session_proposals_json.session_proposals,
        'total', totals.total
    )
    from session_proposals_json, totals;
$$ language sql;
