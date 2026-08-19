-- Claims the next durable credit note after its customer refund succeeds.
create or replace function claim_event_purchase_credit_note(
    p_payment_provider_id text
)
returns jsonb as $$
declare
    v_claim_id uuid := gen_random_uuid();
    v_connected_seller_id text;
    v_credit_note event_purchase_credit_note;
    v_event_purchase_id uuid;
    v_provider_invoice_id text;
    v_provider_refund_id text;
begin
    -- Surface an abandoned final attempt without losing provider diagnostics
    update event_purchase_credit_note epcn
    set
        claim_id = null,
        claimed_at = null,
        failure_message = case
            -- Record expiration as the only diagnostic when no provider error exists
            when failure_message is null then
                'Credit-note worker claim expired after the final automatic attempt; provider outcome is unknown'
            -- Retain the provider error and add one final-attempt expiration notice
            else concat(
                failure_message,
                E'\nCredit-note worker claim expired after the final automatic attempt; provider outcome is unknown'
            )
        end,
        status = 'failed',
        updated_at = current_timestamp
    where epcn.payment_provider_id = p_payment_provider_id
    and epcn.attempt_count >= 10
    and epcn.status = 'processing'
    and epcn.claimed_at < current_timestamp - interval '15 minutes';

    -- Claim due work or a claim abandoned by an interrupted worker
    select epcn.*
    into v_credit_note
    from event_purchase_credit_note epcn
    join event_purchase_refund epr using (event_purchase_refund_id)
    where epcn.payment_provider_id = p_payment_provider_id
    and epr.provider_refunded_at is not null
    and (
        (
            epcn.attempt_count < 10
            and epcn.status in ('failed', 'pending')
            and epcn.next_attempt_at <= current_timestamp
        )
        or (
            epcn.attempt_count < 10
            and epcn.status = 'processing'
            and epcn.claimed_at < current_timestamp - interval '15 minutes'
        )
    )
    order by epcn.next_attempt_at, epcn.created_at,
        epcn.event_purchase_credit_note_id
    for update of epcn skip locked
    limit 1;

    -- Return idle state when no compatible work is due
    if not found then
        return null;
    end if;

    -- Persist ownership before returning work to the provider worker
    update event_purchase_credit_note
    set
        attempt_count = attempt_count + 1,
        claim_id = v_claim_id,
        claimed_at = current_timestamp,
        status = 'processing',
        updated_at = current_timestamp
    where event_purchase_credit_note_id =
        v_credit_note.event_purchase_credit_note_id
    returning * into v_credit_note;

    -- Resolve immutable invoice, refund, and account references
    select
        ep.connected_seller_id,
        ep.event_purchase_id,
        ep.provider_invoice_id,
        epr.provider_refund_id
    into
        v_connected_seller_id,
        v_event_purchase_id,
        v_provider_invoice_id,
        v_provider_refund_id
    from event_purchase_refund epr
    join event_purchase ep using (event_purchase_id)
    where epr.event_purchase_refund_id = v_credit_note.event_purchase_refund_id;

    -- Reject claims whose immutable provider context is incomplete
    if nullif(btrim(v_connected_seller_id), '') is null
       or nullif(btrim(v_provider_invoice_id), '') is null
       or nullif(btrim(v_provider_refund_id), '') is null then
        raise exception 'credit note is missing provider context';
    end if;

    -- Return the claimed credit-note contract
    return jsonb_build_object(
        'amount_minor', v_credit_note.amount_minor,
        'claim_id', v_credit_note.claim_id,
        'connected_seller_id', v_connected_seller_id,
        'event_purchase_credit_note_id',
            v_credit_note.event_purchase_credit_note_id,
        'event_purchase_id', v_event_purchase_id,
        'event_purchase_refund_id', v_credit_note.event_purchase_refund_id,
        'idempotency_key', v_credit_note.idempotency_key,
        'provider_invoice_id', v_provider_invoice_id,
        'provider_refund_id', v_provider_refund_id,
        'tax_amount_minor', v_credit_note.tax_amount_minor
    );
end;
$$ language plpgsql;
