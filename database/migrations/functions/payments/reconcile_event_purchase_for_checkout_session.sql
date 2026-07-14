-- Reconciles a completed provider checkout session with its local purchase.
create or replace function reconcile_event_purchase_for_checkout_session(
    p_provider text,
    p_provider_session_id text,
    p_provider_payment_reference text
)
returns jsonb as $$
declare
    v_amount_minor bigint;
    v_community_id uuid;
    v_event_discount_code_id uuid;
    v_event_id uuid;
    v_hold_expired boolean;
    v_provider_payment_reference text;
    v_purchase_id uuid;
    v_recovery_pending boolean;
    v_status text;
    v_unfulfillable boolean;
    v_user_id uuid;
begin
    -- Resolve and lock the event before its checkout purchase
    select ep.event_id
    into v_event_id
    from event_purchase ep
    where ep.payment_provider_id = p_provider
    and ep.provider_checkout_session_id = p_provider_session_id;

    if not found then
        return jsonb_build_object('outcome', 'noop');
    end if;

    perform 1
    from event
    where event_id = v_event_id
    for update;

    -- Lock the purchase before deciding how to reconcile the provider checkout
    select
        ep.amount_minor,
        g.community_id,
        ep.event_discount_code_id,
        ep.event_id,
        ep.hold_expires_at is not null
            and ep.hold_expires_at <= current_timestamp,
        coalesce(p_provider_payment_reference, ep.provider_payment_reference),
        ep.event_purchase_id,
        exists (
            select 1
            from event_purchase recovery_ep
            where recovery_ep.event_id = ep.event_id
            and recovery_ep.event_purchase_id <> ep.event_purchase_id
            and recovery_ep.status = 'refund-recovery-pending'
            and recovery_ep.user_id = ep.user_id
        ),
        ep.status,
        e.canceled
            or e.deleted
            or not e.published
            or not g.active
            or (
                coalesce(e.ends_at, e.starts_at) is not null
                and coalesce(e.ends_at, e.starts_at) <= current_timestamp
            ),
        ep.user_id
    into
        v_amount_minor,
        v_community_id,
        v_event_discount_code_id,
        v_event_id,
        v_hold_expired,
        v_provider_payment_reference,
        v_purchase_id,
        v_recovery_pending,
        v_status,
        v_unfulfillable,
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
        v_status in ('pending', 'refund-pending')
        or (
            v_status = 'expired'
            and v_hold_expired
        )
    ) then
        return jsonb_build_object('outcome', 'noop');
    end if;

    -- Complete active holds even if public registration has closed since checkout started
    if v_status <> 'refund-pending'
       and not v_hold_expired
       and not v_recovery_pending
       and not v_unfulfillable then
        -- Add the attendee, reviving only checkout-compatible states
        insert into event_attendee (event_id, user_id)
        values (v_event_id, v_user_id)
        on conflict (event_id, user_id) do update
        set status = 'confirmed'
        where event_attendee.status in ('confirmed', 'invitation-canceled', 'registration-questions-pending');

        if found then
            -- Persist the completed purchase state after the attendee is recorded
            update event_purchase
            set
                completed_at = current_timestamp,
                hold_expires_at = null,
                provider_payment_reference = v_provider_payment_reference,
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
        end if;
    end if;

    -- Refund purchases that cannot be completed or are awaiting refund retry,
    -- requiring a provider payment reference before the refund handoff
    if v_provider_payment_reference is null then
        raise exception 'provider payment reference is required for refund';
    end if;

    -- Persist the refund-pending state before the provider refund step
    if v_status <> 'refund-pending' then
        update event_purchase
        set
            hold_expires_at = null,
            provider_payment_reference = v_provider_payment_reference,
            status = 'refund-pending',
            updated_at = current_timestamp
        where event_purchase_id = v_purchase_id;

        -- Release the discount reservation only when expiring a pending hold
        if v_status = 'pending' and v_event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_event_discount_code_id);
        end if;

        -- Release the pending attendee row created for checkout answers
        perform release_event_checkout_attendee_hold(v_event_id, v_user_id);
    end if;

    return jsonb_build_object(
        'amount_minor', v_amount_minor,
        'event_purchase_id', v_purchase_id,
        'outcome', 'refund_required',
        'provider_payment_reference', v_provider_payment_reference
    );
end;
$$ language plpgsql;
