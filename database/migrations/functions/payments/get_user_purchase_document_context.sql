-- Resolves an attendee-owned provider document through immutable account scope.
create or replace function get_user_purchase_document_context(
    p_user_id uuid,
    p_event_purchase_id uuid,
    p_event_purchase_credit_note_id uuid default null
)
returns jsonb as $$
    select to_jsonb(document_context)
    from (
        select
            ep.connected_seller_id,
            ep.payment_provider_id as payment_provider,
            case
                when p_event_purchase_credit_note_id is null
                    then ep.provider_invoice_id
                else epcn.provider_credit_note_id
            end as provider_document_id
        from event_purchase ep
        left join event_purchase_refund epr
            on epr.event_purchase_id = ep.event_purchase_id
            and p_event_purchase_credit_note_id is not null
        left join event_purchase_credit_note epcn
            on epcn.event_purchase_refund_id = epr.event_purchase_refund_id
            and epcn.event_purchase_credit_note_id = p_event_purchase_credit_note_id
            and epcn.status = 'issued'
        where ep.event_purchase_id = p_event_purchase_id
        and ep.user_id = p_user_id
        and ep.amount_minor > 0
        and ep.charge_model = 'direct-charge'
        and ep.status in (
            'completed',
            'refund-pending',
            'refund-recovery-pending',
            'refund-requested',
            'refunded'
        )
        and (
            p_event_purchase_credit_note_id is null
            and ep.provider_invoice_id is not null
            or p_event_purchase_credit_note_id is not null
            and epcn.provider_credit_note_id is not null
        )
    ) document_context;
$$ language sql stable;
