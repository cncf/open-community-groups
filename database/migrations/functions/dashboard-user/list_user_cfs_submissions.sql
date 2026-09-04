-- Returns paginated CFS submissions for a user.
create or replace function list_user_cfs_submissions(p_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse pagination filters
        filters as (
            select
                f.limit_value,
                f.offset_value
            from parse_search_filters(p_filters) f
        ),
        -- Gather paginated submissions
        submissions as (
            select
                cs.cfs_submission_id,
                epoch_seconds(cs.created_at) as created_at,
                get_event_summary(g.community_id, g.group_id, e.event_id) as event,
                json_strip_nulls(json_build_object(
                    'description', sp.description,
                    'duration_minutes', floor(extract(epoch from sp.duration) / 60)::int,
                    'session_proposal_id', sp.session_proposal_id,
                    'session_proposal_level_id', sp.session_proposal_level_id,
                    'session_proposal_level_name', spl.display_name,
                    'title', sp.title,

                    'co_speaker', case
                        when co.user_id is null then null
                        else public_user_summary(co)
                    end
                )) as session_proposal,
                (
                    select coalesce(json_agg(json_build_object(
                        'color', ecl.color,
                        'event_cfs_label_id', ecl.event_cfs_label_id,
                        'name', ecl.name
                    ) order by ecl.name asc, ecl.event_cfs_label_id asc), '[]'::json)
                    from cfs_submission_label csl
                    join event_cfs_label ecl on ecl.event_cfs_label_id = csl.event_cfs_label_id
                    where csl.cfs_submission_id = cs.cfs_submission_id
                ) as labels,
                cs.status_id,
                css.display_name as status_name,

                cs.action_required_message,
                s.session_id as linked_session_id,
                epoch_seconds(cs.updated_at) as updated_at
            from cfs_submission cs
            join session_proposal sp on sp.session_proposal_id = cs.session_proposal_id
            join session_proposal_level spl using (session_proposal_level_id)
            join event e on e.event_id = cs.event_id
            join "group" g on g.group_id = e.group_id
            join cfs_submission_status css on css.cfs_submission_status_id = cs.status_id
            left join "user" co on co.user_id = sp.co_speaker_user_id
            left join session s on s.cfs_submission_id = cs.cfs_submission_id
            where sp.user_id = p_user_id
            order by cs.created_at desc, cs.cfs_submission_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count total submissions
        totals as (
            select count(*)::int as total
            from cfs_submission cs
            join session_proposal sp on sp.session_proposal_id = cs.session_proposal_id
            where sp.user_id = p_user_id
        ),
        -- Aggregate submissions to JSON
        submissions_json as (
            select coalesce(json_agg(row_to_json(submissions)), '[]'::json) as submissions
            from submissions
        )
    select json_build_object(
        'submissions', submissions_json.submissions,
        'total', totals.total
    )
    from submissions_json, totals;
$$ language sql;
