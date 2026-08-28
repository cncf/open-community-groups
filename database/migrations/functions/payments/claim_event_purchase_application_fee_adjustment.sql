-- Claims the next durable application-fee adjustment.
create or replace function claim_event_purchase_application_fee_adjustment(
    p_payment_provider_id text
)
returns jsonb as $$
declare
    v_adjustment event_purchase_application_fee_adjustment;
    v_claim_id uuid := gen_random_uuid();
    v_connected_seller_id text;
    v_currency_code text;
    v_provider_application_fee_id text;
begin
    -- Surface an abandoned final attempt without losing provider diagnostics
    update event_purchase_application_fee_adjustment epafa
    set
        claim_id = null,
        claimed_at = null,
        failure_message = case
            -- Record expiration as the only diagnostic when no provider error exists
            when failure_message is null then
                'Application-fee adjustment worker claim expired after the final automatic attempt; provider outcome is unknown'
            -- Retain the provider error and add one final-attempt expiration notice
            else concat(
                failure_message,
                E'\nApplication-fee adjustment worker claim expired after the final automatic attempt; provider outcome is unknown'
            )
        end,
        status = 'failed',
        updated_at = current_timestamp
    from event_purchase ep
    where epafa.event_purchase_id = ep.event_purchase_id
    and ep.payment_provider_id = p_payment_provider_id
    and epafa.attempt_count >= 10
    and epafa.status = 'processing'
    and epafa.claimed_at < current_timestamp - interval '15 minutes';

    -- Claim due work or a claim abandoned by an interrupted worker
    select epafa.*
    into v_adjustment
    from event_purchase_application_fee_adjustment epafa
    join event_purchase ep using (event_purchase_id)
    where ep.payment_provider_id = p_payment_provider_id
    and ep.provider_application_fee_id is not null
    and (
        (
            epafa.attempt_count < 10
            and epafa.status in ('failed', 'pending')
            and epafa.next_attempt_at <= current_timestamp
        )
        or (
            epafa.attempt_count < 10
            and epafa.status = 'processing'
            and epafa.claimed_at < current_timestamp - interval '15 minutes'
        )
    )
    order by epafa.next_attempt_at, epafa.created_at,
        epafa.event_purchase_application_fee_adjustment_id
    for update of epafa skip locked
    limit 1;

    -- Return idle state when no compatible work is due
    if not found then
        return null;
    end if;

    -- Persist ownership before returning work to the provider worker
    update event_purchase_application_fee_adjustment
    set
        attempt_count = attempt_count + 1,
        claim_id = v_claim_id,
        claimed_at = current_timestamp,
        status = 'processing',
        updated_at = current_timestamp
    where event_purchase_application_fee_adjustment_id =
        v_adjustment.event_purchase_application_fee_adjustment_id
    returning * into v_adjustment;

    -- Resolve immutable provider references from the purchase snapshot
    select
        ep.connected_seller_id,
        ep.currency_code,
        ep.provider_application_fee_id
    into
        v_connected_seller_id,
        v_currency_code,
        v_provider_application_fee_id
    from event_purchase ep
    where ep.event_purchase_id = v_adjustment.event_purchase_id;

    -- Reject claims whose immutable provider context is incomplete
    if nullif(btrim(v_connected_seller_id), '') is null
       or nullif(btrim(v_currency_code), '') is null
       or nullif(btrim(v_provider_application_fee_id), '') is null then
        raise exception 'application-fee adjustment is missing provider context';
    end if;

    -- Return the claimed adjustment contract
    return jsonb_build_object(
        'amount_minor', v_adjustment.amount_minor,
        'claim_id', v_adjustment.claim_id,
        'connected_seller_id', v_connected_seller_id,
        'currency_code', v_currency_code,
        'event_purchase_application_fee_adjustment_id',
            v_adjustment.event_purchase_application_fee_adjustment_id,
        'event_purchase_id', v_adjustment.event_purchase_id,
        'idempotency_key', v_adjustment.idempotency_key,
        'kind', v_adjustment.kind,
        'provider_application_fee_id', v_provider_application_fee_id
    );
end;
$$ language plpgsql;
