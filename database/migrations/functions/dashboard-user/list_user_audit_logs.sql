-- Returns paginated audit log rows for the user dashboard.
create or replace function list_user_audit_logs(p_actor_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse the supported audit log filters
        filters as (
            select
                nullif(p_filters->>'action', '') as action_value,
                nullif(p_filters->>'date_from', '')::date as date_from_value,
                nullif(p_filters->>'date_to', '')::date as date_to_value,
                coalesce((p_filters->>'limit')::int, 50) as limit_value,
                coalesce((p_filters->>'offset')::int, 0) as offset_value,
                coalesce(nullif(p_filters->>'sort', ''), 'created-desc') as sort_value
        ),
        -- Filter rows before pagination
        filtered_logs as (
            select al.*
            from audit_log al
            cross join filters f
            where al.actor_user_id = p_actor_user_id
            and al.action = any(array[
                'community_team_invitation_accepted',
                'community_team_invitation_rejected',
                'group_team_invitation_accepted',
                'group_team_invitation_rejected',
                'session_proposal_added',
                'session_proposal_co_speaker_invitation_accepted',
                'session_proposal_co_speaker_invitation_rejected',
                'session_proposal_deleted',
                'session_proposal_updated',
                'submission_resubmitted',
                'submission_withdrawn',
                'user_details_updated',
                'user_password_updated'
            ]::text[])
            and (f.action_value is null or al.action = f.action_value)
            and (
                f.date_from_value is null
                or al.created_at >= (f.date_from_value::timestamp at time zone 'UTC')
            )
            and (
                f.date_to_value is null
                or al.created_at < (((f.date_to_value + 1)::timestamp) at time zone 'UTC')
            )
        ),
        -- Count total rows before pagination
        totals as (
            select count(*)::int as total
            from filtered_logs
        ),
        -- Select the paginated audit log rows
        logs as (
            select
                fl.action,
                fl.audit_log_id,
                extract(epoch from fl.created_at)::bigint as created_at,
                fl.details,
                fl.resource_id,
                fl.resource_type,

                fl.actor_username,
                case fl.resource_type
                    when 'cfs_submission' then (
                        select sp.title
                        from cfs_submission cs
                        join session_proposal sp using (session_proposal_id)
                        where cs.cfs_submission_id = fl.resource_id
                    )
                    when 'community' then (
                        select c.display_name
                        from community c
                        where c.community_id = fl.resource_id
                    )
                    when 'event' then (
                        select e.name
                        from event e
                        where e.event_id = fl.resource_id
                    )
                    when 'event_category' then (
                        select ec.name
                        from event_category ec
                        where ec.event_category_id = fl.resource_id
                    )
                    when 'group' then (
                        select g.name
                        from "group" g
                        where g.group_id = fl.resource_id
                    )
                    when 'group_category' then (
                        select gc.name
                        from group_category gc
                        where gc.group_category_id = fl.resource_id
                    )
                    when 'group_sponsor' then (
                        select gs.name
                        from group_sponsor gs
                        where gs.group_sponsor_id = fl.resource_id
                    )
                    when 'region' then (
                        select r.name
                        from region r
                        where r.region_id = fl.resource_id
                    )
                    when 'session_proposal' then (
                        select sp.title
                        from session_proposal sp
                        where sp.session_proposal_id = fl.resource_id
                    )
                    when 'user' then (
                        select coalesce(u.name, u.username)
                        from "user" u
                        where u.user_id = fl.resource_id
                    )
                end as resource_name
            from filtered_logs fl
            cross join filters f
            order by
                case when f.sort_value = 'created-asc' then fl.created_at end asc,
                case when f.sort_value = 'created-asc' then fl.audit_log_id end asc,
                case when f.sort_value <> 'created-asc' then fl.created_at end desc,
                case when f.sort_value <> 'created-asc' then fl.audit_log_id end desc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Render rows as JSON
        logs_json as (
            select coalesce(json_agg(row_to_json(logs)), '[]'::json) as logs
            from logs
        )
    -- Build final payload
    select json_build_object(
        'logs', logs_json.logs,
        'total', totals.total
    )
    from logs_json, totals;
$$ language sql;
