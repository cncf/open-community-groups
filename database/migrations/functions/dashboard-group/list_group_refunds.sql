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
                coalesce(
                    epr.amount_minor,
                    ep.provider_total_minor,
                    ep.amount_minor
                ) as amount_minor,
                coalesce(epr.created_at, err.created_at, ep.updated_at) as created_at_sort,
                ep.charge_model,
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
        -- Select exhausted fee and document work requiring operator action
        base_financial_recoveries as (
            select
                epafa.amount_minor,
                epafa.attempt_count,
                ep.currency_code,
                u.email,
                e.event_id,
                e.name as event_name,
                ep.event_purchase_id,
                coalesce(
                    epafa.failure_message,
                    'Provider operation failed without details'
                ) as failure_message,
                'application-fee-adjustment'::text as kind,
                u.name,
                case epafa.kind
                    when 'purchase-refund' then 'Application-fee refund'
                    when 'tax-reconciliation' then 'Tax fee correction'
                end as operation,
                ep.ticket_title,
                epafa.updated_at,
                u.user_id,
                u.username,
                epafa.event_purchase_application_fee_adjustment_id as work_id
            from event_purchase_application_fee_adjustment epafa
            join event_purchase ep using (event_purchase_id)
            join event e using (event_id)
            join "user" u using (user_id)
            where e.group_id = p_group_id
            and epafa.status = 'failed'
            and epafa.attempt_count >= 10

            union all

            select
                epcn.amount_minor,
                epcn.attempt_count,
                epcn.currency_code,
                u.email,
                e.event_id,
                e.name as event_name,
                ep.event_purchase_id,
                coalesce(
                    epcn.failure_message,
                    'Provider operation failed without details'
                ) as failure_message,
                'credit-note'::text as kind,
                u.name,
                'Credit note'::text as operation,
                ep.ticket_title,
                epcn.updated_at,
                u.user_id,
                u.username,
                epcn.event_purchase_credit_note_id as work_id
            from event_purchase_credit_note epcn
            join event_purchase_refund epr using (event_purchase_refund_id)
            join event_purchase ep using (event_purchase_id)
            join event e using (event_id)
            join "user" u using (user_id)
            where e.group_id = p_group_id
            and epcn.status = 'failed'
            and epcn.attempt_count >= 10
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
        -- Apply the shared event, search, and operational view filters
        filtered_financial_recoveries as (
            select bfr.*
            from base_financial_recoveries bfr
            cross join filters f
            where f.view_value <> 'completed'
            and (
                f.event_id_value is null
                or bfr.event_id = f.event_id_value
            )
            and (
                f.ts_query_value is null
                or concat_ws(
                    ' ',
                    bfr.email,
                    bfr.event_name,
                    bfr.name,
                    bfr.operation,
                    bfr.ticket_title,
                    bfr.username
                ) ilike '%' || escape_ilike_pattern(f.ts_query_value) || '%'
            )
        ),
        -- Combine refund and financial-recovery work into one bounded page
        operational_items as (
            select
                fr.event_purchase_id as item_id,
                'refund'::text as item_type,
                fr.updated_at_sort as updated_at
            from filtered_refunds fr

            union all

            select
                ffr.work_id as item_id,
                'financial-recovery'::text as item_type,
                ffr.updated_at
            from filtered_financial_recoveries ffr
        ),
        paged_operational_items as (
            select item_id, item_type, updated_at
            from operational_items
            order by updated_at desc, item_type, item_id desc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Select refund rows represented on the requested operational page
        refunds as (
            select
                fr.amount_minor,
                extract(epoch from fr.created_at_sort)::bigint as created_at,
                fr.currency_code,
                fr.email,
                fr.event_id,
                fr.event_name,
                fr.event_purchase_id,
                fr.charge_model = 'external' as external,
                fr.status,
                fr.ticket_title,
                extract(epoch from fr.updated_at_sort)::bigint as updated_at,
                fr.user_id,
                fr.username,

                fr.attempt_count,
                fr.failure_message,
                fr.kind,
                fr.name,
                fr.photo_url,
                fr.provider_refund_id,
                fr.requested_reason,
                fr.review_note
            from filtered_refunds fr
            join paged_operational_items poi
                on poi.item_id = fr.event_purchase_id
                and poi.item_type = 'refund'
            order by fr.updated_at_sort desc, fr.event_purchase_id desc
        ),
        -- Select recovery rows represented on the requested operational page
        financial_recoveries as (
            select
                ffr.amount_minor,
                ffr.attempt_count,
                ffr.currency_code,
                ffr.email,
                ffr.event_name,
                ffr.failure_message,
                ffr.kind,
                ffr.operation,
                ffr.username,
                ffr.work_id,

                ffr.name,
                ffr.updated_at as updated_at_sort
            from filtered_financial_recoveries ffr
            join paged_operational_items poi
                on poi.item_id = ffr.work_id
                and poi.item_type = 'financial-recovery'
            order by ffr.updated_at desc, ffr.work_id desc
        ),
        -- List events represented in the group's refund history
        events as (
            select distinct
                event_id,
                event_name as name
            from base_refunds

            union

            select distinct
                event_id,
                event_name as name
            from base_financial_recoveries

            order by name asc, event_id asc
        ),
        -- Count matching rows before pagination
        totals as (
            select count(*)::int as total
            from operational_items
        ),
        -- Render event options and refund rows as JSON
        events_json as (
            select coalesce(
                json_agg(row_to_json(events) order by name asc, event_id asc),
                '[]'::json
            ) as events
            from events
        ),
        financial_recoveries_json as (
            select coalesce(
                json_agg(
                    json_build_object(
                        'amount_minor', amount_minor,
                        'attempt_count', attempt_count,
                        'currency_code', currency_code,
                        'email', email,
                        'event_name', event_name,
                        'failure_message', failure_message,
                        'kind', kind,
                        'operation', operation,
                        'username', username,
                        'work_id', work_id,
                        'name', name
                    )
                    order by updated_at_sort desc, work_id desc
                ),
                '[]'::json
            ) as financial_recoveries
            from financial_recoveries
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
        'financial_recoveries', financial_recoveries_json.financial_recoveries,
        'refunds', refunds_json.refunds,
        'total', totals.total
    )
    from events_json, financial_recoveries_json, refunds_json, totals;
$$ language sql;
