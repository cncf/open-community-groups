-- Returns approved CFS submissions for an event.
create or replace function list_event_approved_cfs_submissions(p_event_id uuid)
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'cfs_submission_id', cs.cfs_submission_id,
                'label_ids', array(
                    select csl.event_label_id
                    from cfs_submission_label csl
                    join event_label el on el.event_label_id = csl.event_label_id
                    where csl.cfs_submission_id = cs.cfs_submission_id
                    order by el.name asc, el.event_label_id asc
                ),
                'session_proposal_id', sp.session_proposal_id,
                'title', sp.title,

                'speaker_name', coalesce(u.name, u.username)
            )
            order by sp.title asc, cs.cfs_submission_id asc
        ),
        '[]'::json
    )
    from cfs_submission cs
    join session_proposal sp on sp.session_proposal_id = cs.session_proposal_id
    join "user" u on u.user_id = sp.user_id
    where cs.event_id = p_event_id
    and cs.status_id = 'approved';
$$ language sql;
