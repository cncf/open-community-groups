-- Returns reviewer-available CFS submission statuses.
create or replace function list_cfs_submission_statuses_for_review()
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'cfs_submission_status_id', css.cfs_submission_status_id,
                'display_name', css.display_name
            )
            order by css.cfs_submission_status_id
        ),
        '[]'::json
    )
    from cfs_submission_status css
    where css.cfs_submission_status_id <> 'withdrawn';
$$ language sql;
