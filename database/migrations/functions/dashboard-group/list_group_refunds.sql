-- Returns paginated purchase refund workflows for a group.
create or replace function list_group_refunds(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse list filters and normalize the operational view
        filters as (
            select
                (p_filters->>'event_id')::uuid as event_id_value,
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value,
                nullif(btrim(p_filters->>'ts_query'), '') as ts_query_value,
                case
                    when lower(p_filters->>'view') in (
                        'active',
                        'all',
                        'attention',
                        'completed'
                    ) then lower(p_filters->>'view')
                    else 'active'
                end as view_value
        ),
        -- Select every purchase that has entered a refund workflow
        base_refunds as (
            select
                ep.amount_minor,
                coalesce(epr.created_at, err.created_at, ep.updated_at) as created_at_sort,
                ep.currency_code,
                u.email,
                e.event_id,
                e.name as event_name,
                ep.event_purchase_id,
                ep.ticket_title,
                greatest(ep.updated_at, err.updated_at, epr.updated_at) as updated_at_sort,
                u.user_id,
                u.username,

                epr.attempt_count,
                epr.failure_message,
                coalesce(
                    epr.kind,
                    case
                        when err.event_refund_request_id is not null
                            then 'refund-request-approval'
                    end
                ) as kind,
                u.name,
                u.photo_url,
                epr.provider_refund_id,
                err.requested_reason,
                coalesce(epr.review_note, err.review_note) as review_note,
                case
                    when epr.status = 'finalized' or ep.status = 'refunded'
                        then 'refunded'
                    when err.status = 'rejected' and epr.event_purchase_refund_id is null
                        then 'rejected'
                    when err.status = 'pending' and epr.event_purchase_refund_id is null
                        then 'needs-review'
                    when ep.status = 'refund-recovery-pending'
                        or (epr.status = 'provider-failed' and epr.terminal_failure)
                        then 'recovery-required'
                    when epr.status in ('provider-failed', 'provider-pending')
                        and epr.attempt_count >= 10
                        then 'retryable-failure'
                    when epr.status in ('processing', 'provider-succeeded')
                        or (
                            epr.status = 'provider-pending'
                            and epr.provider_refund_id is not null
                        )
                        then 'processing'
                    when epr.status in ('provider-failed', 'provider-pending')
                        then 'queued'
                    when ep.status = 'refund-pending'
                        or (e.canceled and ep.status = 'pending')
                        then 'awaiting-checkout'
                    when err.status = 'approving'
                        then 'processing'
                    else 'queued'
                end as status
            from event_purchase ep
            join event e using (event_id)
            join "user" u using (user_id)
            left join event_refund_request err using (event_purchase_id)
            left join event_purchase_refund epr using (event_purchase_id)
            where e.group_id = p_group_id
            and (
                err.event_refund_request_id is not null
                or epr.event_purchase_refund_id is not null
                or ep.status in (
                    'refund-pending',
                    'refund-recovery-pending',
                    'refund-requested',
                    'refunded'
                )
                or (
                    e.canceled
                    and ep.status = 'pending'
                    and (
                        ep.hold_expires_at > current_timestamp
                        or ep.provider_checkout_session_id is not null
                    )
                )
            )
        ),
        -- Apply the selected operational, event, and text filters
        filtered_refunds as (
            select br.*
            from base_refunds br
            cross join filters f
            where (
                f.event_id_value is null
                or br.event_id = f.event_id_value
            )
            and (
                f.ts_query_value is null
                or concat_ws(
                    ' ',
                    br.email,
                    br.event_name,
                    br.name,
                    br.ticket_title,
                    br.username
                ) ilike '%' || escape_ilike_pattern(f.ts_query_value) || '%'
            )
            and (
                f.view_value = 'all'
                or (
                    f.view_value = 'active'
                    and br.status not in ('refunded', 'rejected')
                )
                or (
                    f.view_value = 'attention'
                    and br.status in (
                        'needs-review',
                        'recovery-required',
                        'retryable-failure'
                    )
                )
                or (
                    f.view_value = 'completed'
                    and br.status in ('refunded', 'rejected')
                )
            )
        ),
        -- Select the requested page
        refunds as (
            select
                amount_minor,
                extract(epoch from created_at_sort)::bigint as created_at,
                currency_code,
                email,
                event_id,
                event_name,
                event_purchase_id,
                status,
                ticket_title,
                extract(epoch from updated_at_sort)::bigint as updated_at,
                user_id,
                username,

                attempt_count,
                failure_message,
                kind,
                name,
                photo_url,
                provider_refund_id,
                requested_reason,
                review_note
            from filtered_refunds
            order by updated_at_sort desc, event_purchase_id desc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- List events represented in the group's refund history
        events as (
            select distinct
                event_id,
                event_name as name
            from base_refunds
            order by name asc, event_id asc
        ),
        -- Count matching rows before pagination
        totals as (
            select count(*)::int as total
            from filtered_refunds
        ),
        -- Render event options and refund rows as JSON
        events_json as (
            select coalesce(
                json_agg(row_to_json(events) order by name asc, event_id asc),
                '[]'::json
            ) as events
            from events
        ),
        refunds_json as (
            select coalesce(
                json_agg(
                    row_to_json(refunds)
                    order by updated_at desc, event_purchase_id desc
                ),
                '[]'::json
            ) as refunds
            from refunds
        )
    -- Build the final payload
    select json_build_object(
        'events', events_json.events,
        'refunds', refunds_json.refunds,
        'total', totals.total
    )
    from events_json, refunds_json, totals;
$$ language sql;
