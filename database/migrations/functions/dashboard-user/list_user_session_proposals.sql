-- Returns paginated session proposals for a user.
create or replace function list_user_session_proposals(p_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse pagination filters
        filters as (
            select
                f.limit_value,
                f.offset_value
            from parse_search_filters(p_filters) f
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
                session_proposal_json(sp) || jsonb_build_object(
                    'session_proposal_status_id', sp.session_proposal_status_id,
                    'status_name', sps.display_name,

                    'linked_session_id', pl.linked_session_id,

                    'created_at', epoch_seconds(sp.created_at),
                    'has_submissions', (pl.submission_count > 0),
                    'updated_at', epoch_seconds(sp.updated_at)
                ) as session_proposal
            from session_proposal sp
            join session_proposal_status sps
                on sps.session_proposal_status_id = sp.session_proposal_status_id
            left join session_proposal_links pl on pl.session_proposal_id = sp.session_proposal_id
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
            select coalesce(json_agg(session_proposal), '[]'::json) as session_proposals
            from session_proposals
        )
    select json_build_object(
        'session_proposals', session_proposals_json.session_proposals,
        'total', totals.total
    )
    from session_proposals_json, totals;
$$ language sql stable;
