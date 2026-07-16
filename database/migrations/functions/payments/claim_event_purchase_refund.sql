-- Claims the next refund ready for a configured payments provider.
create or replace function claim_event_purchase_refund(
    p_payment_provider_id text
)
returns jsonb as $$
declare
    v_claim_id uuid := gen_random_uuid();
    v_community_id uuid;
    v_event_id uuid;
    v_provider_payment_reference text;
    v_refund event_purchase_refund;
begin
    -- Claim provider-complete work first, then due provider reconciliation work
    select epr.*
    into v_refund
    from event_purchase_refund epr
    where epr.payment_provider_id = p_payment_provider_id
    and epr.next_attempt_at <= current_timestamp
    and (
        epr.status = 'provider-succeeded'
        or (
            epr.status = 'provider-pending'
            and epr.attempt_count < 10
        )
        or (
            epr.status = 'provider-failed'
            and not epr.terminal_failure
            and epr.attempt_count < 10
        )
    )
    order by
        case when epr.status = 'provider-succeeded' then 0 else 1 end,
        epr.next_attempt_at,
        epr.created_at,
        epr.event_purchase_refund_id
    for update skip locked
    limit 1;

    if not found then
        return null;
    end if;

    -- Pin the claim so only this worker can release or complete it
    update event_purchase_refund
    set
        attempt_count = case
            when v_refund.status = 'provider-succeeded' then attempt_count
            else attempt_count + 1
        end,
        claim_id = v_claim_id,
        claimed_at = current_timestamp,
        status = 'processing',
        updated_at = current_timestamp
    where event_purchase_refund_id = v_refund.event_purchase_refund_id
    returning * into v_refund;

    -- Resolve the purchase and notification context required by the worker
    select
        g.community_id,
        ep.event_id,
        ep.provider_payment_reference
    into
        v_community_id,
        v_event_id,
        v_provider_payment_reference
    from event_purchase ep
    join event e using (event_id)
    join "group" g using (group_id)
    where ep.event_purchase_id = v_refund.event_purchase_id;

    if not found then
        raise exception 'event purchase not found';
    end if;

    -- Return all state required for a provider call outside this transaction
    return jsonb_strip_nulls(
        jsonb_build_object(
            'amount_minor', v_refund.amount_minor,
            'community_id', v_community_id,
            'currency_code', v_refund.currency_code,
            'event_id', v_event_id,
            'event_purchase_id', v_refund.event_purchase_id,
            'event_purchase_refund_id', v_refund.event_purchase_refund_id,
            'idempotency_key', v_refund.idempotency_key,
            'kind', v_refund.kind,
            'payment_provider', v_refund.payment_provider_id,
            'status', v_refund.status,
            'terminal_failure', v_refund.terminal_failure,

            'attempt_count', v_refund.attempt_count,
            'claim_id', v_refund.claim_id,
            'failure_message', v_refund.failure_message,
            'finalized_at', extract(epoch from v_refund.finalized_at)::bigint,
            'provider_payment_reference', v_provider_payment_reference,
            'provider_refund_id', v_refund.provider_refund_id,
            'provider_refunded_at', extract(epoch from v_refund.provider_refunded_at)::bigint
        )
    );
end;
$$ language plpgsql;
