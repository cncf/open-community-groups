-- Attaches an account-scoped paid invoice to its immutable purchase.
create or replace function attach_invoice_to_event_purchase(
    p_event_purchase_id uuid,
    p_connected_seller_id text,
    p_provider_invoice_id text,
    p_provider_invoice_hosted_url text,
    p_provider_invoice_pdf_url text default null
)
returns void as $$
declare
    v_purchase event_purchase;
    v_refund event_purchase_refund;
begin
    -- Lock and validate the purchase's provider account scope
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.event_purchase_id = p_event_purchase_id
    for update;

    if not found then
        raise exception 'event purchase not found';
    end if;

    if v_purchase.charge_model <> 'direct-charge'
       or v_purchase.provider_object_account_id <> p_connected_seller_id then
        raise exception 'invoice account does not match the purchase seller';
    end if;

    if v_purchase.provider_invoice_id is not null
       and v_purchase.provider_invoice_id <> p_provider_invoice_id then
        raise exception 'event purchase already has a different provider invoice';
    end if;

    -- Refresh provider URLs without replacing the durable invoice identifier
    update event_purchase
    set
        provider_invoice_hosted_url = p_provider_invoice_hosted_url,
        provider_invoice_id = p_provider_invoice_id,
        provider_invoice_pdf_url = p_provider_invoice_pdf_url,
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Queue a linked credit note when a refund arrived before its invoice
    select epr.*
    into v_refund
    from event_purchase_refund epr
    where epr.event_purchase_id = p_event_purchase_id
    and epr.provider_refunded_at is not null;

    if found then
        insert into event_purchase_credit_note (
            amount_minor,
            currency_code,
            event_purchase_refund_id,
            idempotency_key,
            payment_provider_id,
            provider_object_account_id,
            tax_amount_minor
        ) values (
            v_purchase.provider_total_minor,
            v_purchase.currency_code,
            v_refund.event_purchase_refund_id,
            format('event-purchase-credit-note-%s', v_refund.event_purchase_refund_id),
            v_purchase.payment_provider_id,
            v_purchase.provider_object_account_id,
            v_purchase.tax_amount_minor
        )
        on conflict (event_purchase_refund_id) do nothing;
    end if;
end;
$$ language plpgsql;
