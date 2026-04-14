-- Used by the checkout-completed webhook handler: reconciles the provider
-- checkout session with the local purchase by completing it, returning noop,
-- or marking it for automatic refund when it can no longer be fulfilled
create or replace function reconcile_event_purchase_for_checkout_session(
    p_provider text,
    p_provider_session_id text,
    p_provider_payment_reference text
)
returns jsonb as $$
declare
    v_amount_minor bigint;
    v_community_id uuid;
    v_event_canceled boolean;
    v_event_discount_code_id uuid;
    v_event_deleted boolean;
    v_event_id uuid;
    v_event_published boolean;
    v_group_active boolean;
    v_hold_expires_at timestamptz;
    v_provider_payment_reference text;
    v_purchase_id uuid;
    v_status text;
    v_user_id uuid;
begin
    -- Lock the purchase before deciding how to reconcile the provider checkout
    select
        ep.amount_minor,
        g.community_id,
        e.canceled,
        ep.event_discount_code_id,
        e.deleted,
        ep.event_id,
        e.published,
        g.active,
        ep.hold_expires_at,
        coalesce(p_provider_payment_reference, ep.provider_payment_reference),
        ep.event_purchase_id,
        ep.status,
        ep.user_id
    into
        v_amount_minor,
        v_community_id,
        v_event_canceled,
        v_event_discount_code_id,
        v_event_deleted,
        v_event_id,
        v_event_published,
        v_group_active,
        v_hold_expires_at,
        v_provider_payment_reference,
        v_purchase_id,
        v_status,
        v_user_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where ep.payment_provider_id = p_provider
    and ep.provider_checkout_session_id = p_provider_session_id
    for update of ep;

    -- Return a noop when the checkout session does not match any purchase
    if not found then
        return jsonb_build_object('outcome', 'noop');
    end if;

    -- Ignore purchases that are already reconciled
    if not (
        v_status = 'pending'
        or (
            v_status = 'expired'
            and v_hold_expires_at is not null
            and v_hold_expires_at <= current_timestamp
        )
    ) then
        return jsonb_build_object('outcome', 'noop');
    end if;

    -- Refund purchases whose hold has already expired locally
    if v_status in ('pending', 'expired')
       and v_hold_expires_at is not null
       and v_hold_expires_at <= current_timestamp then
        -- Require a provider payment reference before requesting a refund
        if v_provider_payment_reference is null then
            raise exception 'provider payment reference is required for refund';
        end if;

        -- Persist the expired purchase state before the refund step
        update event_purchase
        set
            hold_expires_at = null,
            provider_payment_reference = v_provider_payment_reference,
            status = 'expired',
            updated_at = current_timestamp
        where event_purchase_id = v_purchase_id;

        -- Release the discount reservation only when expiring a pending hold
        if v_status = 'pending' and v_event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_event_discount_code_id);
        end if;

        return jsonb_build_object(
            'amount_minor', v_amount_minor,
            'event_purchase_id', v_purchase_id,
            'outcome', 'refund_required',
            'provider_payment_reference', v_provider_payment_reference
        );
    end if;

    -- Refund purchases that can no longer be fulfilled locally
    if v_event_canceled or v_event_deleted or not v_event_published or not v_group_active then
        -- Require a provider payment reference before requesting a refund
        if v_provider_payment_reference is null then
            raise exception 'provider payment reference is required for refund';
        end if;

        -- Persist the expired purchase state before the refund step
        update event_purchase
        set
            hold_expires_at = null,
            provider_payment_reference = v_provider_payment_reference,
            status = 'expired',
            updated_at = current_timestamp
        where event_purchase_id = v_purchase_id;

        -- Release the discount reservation only when expiring a pending hold
        if v_status = 'pending' and v_event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_event_discount_code_id);
        end if;

        return jsonb_build_object(
            'amount_minor', v_amount_minor,
            'event_purchase_id', v_purchase_id,
            'outcome', 'refund_required',
            'provider_payment_reference', v_provider_payment_reference
        );
    end if;

    -- Complete the purchase and add the attendee when it is still fulfillable
    insert into event_attendee (event_id, user_id)
    values (v_event_id, v_user_id)
    on conflict (event_id, user_id) do nothing;

    -- Persist the completed purchase state after the attendee is recorded
    update event_purchase
    set
        completed_at = current_timestamp,
        hold_expires_at = null,
        provider_payment_reference = coalesce(v_provider_payment_reference, provider_payment_reference),
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_id = v_purchase_id;

    -- Return the identifiers needed by downstream notification flows
    return jsonb_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id,
        'outcome', 'completed',
        'user_id', v_user_id
    );
end;
$$ language plpgsql;
