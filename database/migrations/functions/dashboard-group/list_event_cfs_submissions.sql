-- Returns paginated CFS submissions for an event.
create or replace function list_event_cfs_submissions(p_event_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse pagination and sorting filters
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value,
                case
                    when lower(p_filters->>'sort') in (
                        'created-asc',
                        'created-desc',
                        'ratings-count-asc',
                        'ratings-count-desc',
                        'stars-asc',
                        'stars-desc'
                    ) then lower(p_filters->>'sort')
                    else 'created-desc'
                end as sort_value
        ),
        -- Parse selected label filters
        label_filter as (
            select
                count(*)::int as labels_total,
                coalesce(array_agg(label_id), '{}') as selected_label_ids
            from (
                select value::uuid as label_id
                from jsonb_array_elements_text(coalesce(p_filters->'label_ids', '[]'::jsonb))
            ) input_labels
        ),
        -- Filter submissions for the event
        filtered_submissions as (
            select
                cs.action_required_message,
                cs.cfs_submission_id,
                cs.created_at,
                cs.event_id,
                cs.reviewed_by,
                cs.session_proposal_id,
                cs.status_id,
                cs.updated_at
            from cfs_submission cs
            where cs.event_id = p_event_id
            and cs.status_id <> 'withdrawn'
            and (
                (select labels_total from label_filter) = 0
                or cs.cfs_submission_id in (
                    select csl.cfs_submission_id
                    from cfs_submission_label csl
                    where csl.event_cfs_label_id in (
                        select unnest(selected_label_ids)
                        from label_filter
                    )
                    group by csl.cfs_submission_id
                    having count(distinct csl.event_cfs_label_id) = (select labels_total from label_filter)
                )
            )
        ),
        -- Aggregate ratings used for sorting and summaries
        rating_summaries as (
            select
                csr.cfs_submission_id,
                round(avg(csr.stars)::numeric, 1)::double precision as average_rating,
                count(*)::int as ratings_count
            from cfs_submission_rating csr
            join filtered_submissions fs on fs.cfs_submission_id = csr.cfs_submission_id
            group by csr.cfs_submission_id
        ),
        -- Rank submissions according to selected sorting
        ordered_submission_ids as (
            select
                fs.cfs_submission_id,
                row_number() over (
                    order by
                        case
                            when f.sort_value in ('stars-asc', 'stars-desc')
                                and coalesce(rs.ratings_count, 0) = 0 then 1
                            else 0
                        end asc,
                        case
                            when f.sort_value = 'created-asc' then fs.created_at
                        end asc nulls last,
                        case
                            when f.sort_value = 'created-desc' then fs.created_at
                        end desc nulls last,
                        case
                            when f.sort_value = 'ratings-count-asc' then coalesce(rs.ratings_count, 0)
                        end asc nulls last,
                        case
                            when f.sort_value = 'ratings-count-desc' then coalesce(rs.ratings_count, 0)
                        end desc nulls last,
                        case
                            when f.sort_value = 'stars-asc' then rs.average_rating
                        end asc nulls last,
                        case
                            when f.sort_value = 'stars-desc' then rs.average_rating
                        end desc nulls last,
                        fs.created_at desc,
                        fs.cfs_submission_id asc
                ) as sort_order
            from filtered_submissions fs
            left join rating_summaries rs on rs.cfs_submission_id = fs.cfs_submission_id
            cross join filters f
        ),
        -- Select the page of submission ids after sorting
        paginated_submission_ids as (
            select
                osi.cfs_submission_id,
                osi.sort_order
            from ordered_submission_ids osi
            order by osi.sort_order asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Build paginated submissions payload
        submissions as (
            select
                fs.cfs_submission_id,
                extract(epoch from fs.created_at)::bigint as created_at,
                json_strip_nulls(json_build_object(
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
                    end
                )) as session_proposal,
                json_strip_nulls(json_build_object(
                    'user_id', u.user_id,
                    'username', u.username,

                    'company', u.company,
                    'name', u.name,
                    'photo_url', u.photo_url,
                    'title', u.title
                )) as speaker,
                coalesce(rs.ratings_count, 0) as ratings_count,
                fs.status_id,
                css.display_name as status_name,
                (
                    select coalesce(json_agg(json_build_object(
                        'color', ecl.color,
                        'event_cfs_label_id', ecl.event_cfs_label_id,
                        'name', ecl.name
                    ) order by ecl.name asc, ecl.event_cfs_label_id asc), '[]'::json)
                    from cfs_submission_label csl
                    join event_cfs_label ecl on ecl.event_cfs_label_id = csl.event_cfs_label_id
                    where csl.cfs_submission_id = fs.cfs_submission_id
                ) as labels,
                (
                    select coalesce(json_agg(json_strip_nulls(json_build_object(
                        'reviewer', json_strip_nulls(json_build_object(
                            'user_id', rating_user.user_id,
                            'username', rating_user.username,

                            'company', rating_user.company,
                            'name', rating_user.name,
                            'photo_url', rating_user.photo_url,
                            'title', rating_user.title
                        )),
                        'stars', csr.stars,

                        'comments', csr.comments
                    )) order by coalesce(csr.updated_at, csr.created_at) desc, csr.reviewer_id asc), '[]'::json)
                    from cfs_submission_rating csr
                    join "user" rating_user on rating_user.user_id = csr.reviewer_id
                    where csr.cfs_submission_id = fs.cfs_submission_id
                ) as ratings,

                fs.action_required_message,
                rs.average_rating,
                s.session_id as linked_session_id,
                case
                    when reviewer.user_id is null then null
                    else json_strip_nulls(json_build_object(
                        'user_id', reviewer.user_id,
                        'username', reviewer.username,

                        'company', reviewer.company,
                        'name', reviewer.name,
                        'photo_url', reviewer.photo_url,
                        'title', reviewer.title
                    ))
                end as reviewed_by,
                extract(epoch from fs.updated_at)::bigint as updated_at
            from paginated_submission_ids psi
            join filtered_submissions fs on fs.cfs_submission_id = psi.cfs_submission_id
            join session_proposal sp on sp.session_proposal_id = fs.session_proposal_id
            join session_proposal_level spl using (session_proposal_level_id)
            join "user" u on u.user_id = sp.user_id
            join cfs_submission_status css on css.cfs_submission_status_id = fs.status_id
            left join "user" co on co.user_id = sp.co_speaker_user_id
            left join "user" reviewer on reviewer.user_id = fs.reviewed_by
            left join rating_summaries rs on rs.cfs_submission_id = fs.cfs_submission_id
            left join session s on s.cfs_submission_id = fs.cfs_submission_id
        ),
        -- Count total submissions
        totals as (
            select count(*)::int as total
            from filtered_submissions
        ),
        -- Aggregate submissions to JSON
        submissions_json as (
            select coalesce(
                json_agg(row_to_json(submissions) order by psi.sort_order asc),
                '[]'::json
            ) as submissions
            from submissions
            join paginated_submission_ids psi using (cfs_submission_id)
        )
    select json_build_object(
        'submissions', submissions_json.submissions,
        'total', totals.total
    )
    from submissions_json, totals;
$$ language sql;
