-- Returns paginated audit log rows for the user dashboard.
create or replace function list_user_audit_logs(p_actor_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse the supported audit log filters
        filters as (
            select
                nullif(p_filters->>'action', '') as action_value,
                f.date_from as date_from_value,
                f.date_to as date_to_value,
                coalesce(f.limit_value, 50) as limit_value,
                coalesce(f.offset_value, 0) as offset_value,
                case
                    when f.sort in ('created-asc', 'created-desc')
                        then f.sort
                    else 'created-desc'
                end as sort_value
            from parse_search_filters(p_filters) f
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
                'event_attendee_invitation_accepted',
                'event_attendee_invitation_rejected',
                'group_team_invitation_accepted',
                'group_team_invitation_rejected',
                'inbox_conversation_started',
                'inbox_message_sent',
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
                epoch_seconds(fl.created_at) as created_at,
                fl.details,
                fl.resource_id,
                fl.resource_type,

                fl.actor_username,
                audit_log_resource_name(fl.resource_type, fl.resource_id) as resource_name
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
