-- Returns one page of audit log rows for exactly one scope (a community, a
-- group or an actor), limited to the given actions. Uses PL/pgSQL with custom
-- plans for argument-aware plans, so the null scope predicates fold away and
-- each scope walks its (scope, created_at desc) index.
create or replace function search_audit_logs(
    p_community_id uuid,
    p_group_id uuid,
    p_actor_user_id uuid,
    p_actions text[],
    p_filters jsonb
)
returns json as $$
declare
    v_action text;
    v_actor text;
    v_date_from date;
    v_date_to date;
    v_limit int;
    v_offset int;
    v_sort text;
begin
    -- Require exactly one scope
    if num_nonnulls(p_community_id, p_group_id, p_actor_user_id) <> 1 then
        raise exception 'exactly one audit log scope is required';
    end if;

    -- Parse the supported audit log filters
    select
        f.date_from,
        f.date_to,
        coalesce(f.limit_value, 50),
        coalesce(f.offset_value, 0),
        case
            -- Keep a supported sort order
            when f.sort in ('created-asc', 'created-desc') then f.sort
            -- Default unsupported sort orders to newest first
            else 'created-desc'
        end
    into
        v_date_from,
        v_date_to,
        v_limit,
        v_offset,
        v_sort
    from parse_search_filters(p_filters) f;
    v_action := nullif(p_filters->>'action', '');
    v_actor := nullif(p_filters->>'actor', '');

    -- Build the requested page together with the total
    return (
        with
            -- Filter rows of the requested scope before pagination
            filtered_logs as (
                select al.*
                from audit_log al
                where (p_community_id is null or al.community_id = p_community_id)
                and (p_group_id is null or al.group_id = p_group_id)
                and (p_actor_user_id is null or al.actor_user_id = p_actor_user_id)
                and al.action = any(p_actions)
                and (v_action is null or al.action = v_action)
                and (
                    v_actor is null
                    or coalesce(al.actor_username, '') ilike (
                        '%' || escape_ilike_pattern(v_actor) || '%'
                    ) escape '\'
                )
                and (
                    v_date_from is null
                    or al.created_at >= (v_date_from::timestamp at time zone 'UTC')
                )
                and (
                    v_date_to is null
                    or al.created_at < (((v_date_to + 1)::timestamp) at time zone 'UTC')
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
                    audit_log_resource_name(
                        fl.resource_type,
                        fl.resource_id,
                        fl.details
                    ) as resource_name
                from filtered_logs fl
                -- Order by creation time in the requested direction, breaking ties by id
                order by
                    case when v_sort = 'created-asc' then fl.created_at end asc,
                    case when v_sort = 'created-asc' then fl.audit_log_id end asc,
                    case when v_sort <> 'created-asc' then fl.created_at end desc,
                    case when v_sort <> 'created-asc' then fl.audit_log_id end desc
                offset v_offset
                limit v_limit
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
        from logs_json, totals
    );
end;
$$ language plpgsql stable set plan_cache_mode = force_custom_plan;
