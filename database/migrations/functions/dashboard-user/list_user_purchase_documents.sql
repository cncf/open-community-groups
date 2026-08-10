-- Returns durable financial document history for the authenticated attendee.
create or replace function list_user_purchase_documents(p_user_id uuid, p_filters jsonb)
returns json as $$
    with
        purchase_rows as (
            select
                c.name as community_name,
                ep.amount_minor,
                ep.completed_at,
                ep.created_at,
                ep.currency_code,
                e.canceled as event_canceled,
                e.name as event_name,
                e.slug as event_slug,
                e.starts_at as event_starts_at,
                e.timezone as event_timezone,
                ep.event_purchase_id,
                g.name as group_name,
                g.slug as group_slug,
                g.slug_pretty as group_slug_pretty,
                ep.provider_invoice_id,
                ep.provider_total_minor,
                ep.seller_snapshot,
                ep.status,
                ep.ticket_title
            from event_purchase ep
            join event e using (event_id)
            join "group" g using (group_id)
            join community c using (community_id)
            where ep.user_id = p_user_id
            and ep.amount_minor > 0
            and ep.charge_model = 'direct-charge'
            and ep.status in (
                'completed',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested',
                'refunded'
            )
        ),
        purchase_rows_page as (
            select *
            from purchase_rows
            order by coalesce(completed_at, created_at) desc, event_purchase_id desc
            offset (p_filters->>'offset')::int
            limit (p_filters->>'limit')::int
        )
    select json_build_object(
        'purchases',
        (
            select coalesce(
                json_agg(
                    jsonb_build_object(
                        'amount_minor', coalesce(prp.provider_total_minor, prp.amount_minor),
                        'community_name', prp.community_name,
                        'created_at', floor(extract(epoch from prp.created_at)),
                        'credit_notes', coalesce(credit_notes.items, '[]'::jsonb),
                        'currency_code', prp.currency_code,
                        'event_canceled', prp.event_canceled,
                        'event_name', prp.event_name,
                        'event_purchase_id', prp.event_purchase_id,
                        'event_slug', prp.event_slug,
                        'event_timezone', prp.event_timezone,
                        'group_name', prp.group_name,
                        'group_slug', prp.group_slug,
                        'status', prp.status,
                        'ticket_title', prp.ticket_title
                    )
                    || jsonb_strip_nulls(jsonb_build_object(
                        'completed_at', floor(extract(epoch from prp.completed_at)),
                        'event_starts_at', floor(extract(epoch from prp.event_starts_at)),
                        'group_slug_pretty', prp.group_slug_pretty,
                        'provider_invoice_id', prp.provider_invoice_id,
                        'seller_display_name', prp.seller_snapshot->>'display_name'
                    ))
                    order by coalesce(prp.completed_at, prp.created_at) desc,
                        prp.event_purchase_id desc
                ),
                '[]'::json
            )
            from purchase_rows_page prp
            left join lateral (
                select jsonb_agg(
                    jsonb_build_object(
                        'event_purchase_credit_note_id',
                            epcn.event_purchase_credit_note_id,
                        'status', epcn.status
                    )
                    || jsonb_strip_nulls(jsonb_build_object(
                        'provider_credit_note_id', epcn.provider_credit_note_id
                    ))
                    order by epcn.created_at asc,
                        epcn.event_purchase_credit_note_id asc
                ) as items
                from event_purchase_refund epr
                join event_purchase_credit_note epcn using (event_purchase_refund_id)
                where epr.event_purchase_id = prp.event_purchase_id
            ) credit_notes on true
        ),
        'total',
        (select count(*)::int from purchase_rows)
    );
$$ language sql;
