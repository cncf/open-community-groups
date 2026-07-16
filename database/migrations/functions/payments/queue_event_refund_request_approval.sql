-- Queues an approved attendee refund request for worker processing.
create or replace function queue_event_refund_request_approval(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_purchase_id uuid,
    p_review_note text
)
returns void as $$
declare
    v_existing_refund_kind text;
    v_purchase event_purchase;
    v_refund_request_id uuid;
begin
    -- Lock the purchase and refund request before creating durable work
    select ep.*
    into v_purchase
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join event_refund_request err on err.event_purchase_id = ep.event_purchase_id
    where e.group_id = p_group_id
    and ep.event_purchase_id = p_event_purchase_id
    and ep.status = 'refund-requested'
    and err.status in ('approving', 'pending')
    for update of ep;

    if not found then
        raise exception 'refund request not found';
    end if;

    select err.event_refund_request_id
    into v_refund_request_id
    from event_refund_request err
    where err.event_purchase_id = v_purchase.event_purchase_id
    and err.status in ('approving', 'pending')
    for update;

    if not found then
        raise exception 'refund request not found';
    end if;

    -- Preserve the first durable approval decision on idempotent replays
    select epr.kind
    into v_existing_refund_kind
    from event_purchase_refund epr
    where epr.event_purchase_id = v_purchase.event_purchase_id
    for update;

    if found then
        if v_existing_refund_kind <> 'refund-request-approval' then
            raise exception 'event purchase refund already started with different kind';
        end if;

        return;
    end if;

    -- Validate the provider contract before creating durable work
    if v_purchase.amount_minor <= 0
       or v_purchase.payment_provider_id is null
       or v_purchase.provider_payment_reference is null then
        raise exception 'paid purchase is not ready for refund';
    end if;

    -- Persist the review decision before the asynchronous provider handoff
    update event_refund_request
    set
        review_note = nullif(btrim(p_review_note), ''),
        reviewed_at = current_timestamp,
        reviewed_by_user_id = p_actor_user_id,
        status = 'approving',
        updated_at = current_timestamp
    where event_refund_request_id = v_refund_request_id;

    -- Insert the durable worker job with a stable purchase idempotency key
    insert into event_purchase_refund (
        amount_minor,
        currency_code,
        event_purchase_id,
        event_refund_request_id,
        idempotency_key,
        initiated_by_user_id,
        kind,
        payment_provider_id,
        review_note,
        status
    ) values (
        v_purchase.amount_minor,
        v_purchase.currency_code,
        v_purchase.event_purchase_id,
        v_refund_request_id,
        format('event-purchase-refund-%s', v_purchase.event_purchase_id),
        p_actor_user_id,
        'refund-request-approval',
        v_purchase.payment_provider_id,
        nullif(btrim(p_review_note), ''),
        'provider-pending'
    )
    on conflict (event_purchase_id) do nothing;

    -- Reject a purchase already owned by another refund workflow
    perform 1
    from event_purchase_refund
    where event_purchase_id = v_purchase.event_purchase_id
    and kind = 'refund-request-approval';

    if not found then
        raise exception 'event purchase refund already started with different kind';
    end if;
end;
$$ language plpgsql;
