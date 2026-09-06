-- Reconciles a completed provider checkout session with its local purchase:
-- validates and records the authoritative amounts, then either completes the
-- purchase and confirms attendance or, when the purchase can no longer be
-- fulfilled, queues an automatic refund. Sessions without a matching or
-- reconcilable purchase are a noop.
create or replace function reconcile_event_purchase_for_checkout_session(
    p_provider text,
    p_provider_object_account_id text,
    p_provider_session_id text,
    p_provider_payment_reference text,
    p_provider_charge_id text,
    p_provider_total_minor bigint default null,
    p_tax_amount_minor bigint default null,
    p_provider_application_fee_id text default null
)
returns jsonb as $$
declare
    v_admission_offer admission_offer;
    v_event event;
    v_group "group";
    v_hold_expired boolean;
    v_manually_invited boolean;
    v_payment_job_id uuid;
    v_provider_payment_reference text;
    v_purchase event_purchase;
    v_requires_refund boolean;
    v_unfulfillable boolean;
begin
    -- Validate the required direct-charge provider context
    if nullif(btrim(p_provider_object_account_id), '') is null then
        raise exception 'connected seller account is required';
    end if;

    -- Require the payment references a refund or charge lookup would need
    if nullif(btrim(p_provider_payment_reference), '') is null
       or nullif(btrim(p_provider_charge_id), '') is null then
        raise exception 'direct-charge payment references are required';
    end if;

    -- Resolve immutable enrollment identifiers before taking lifecycle locks
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.payment_provider_id = p_provider
    and ep.provider_object_account_id = p_provider_object_account_id
    and ep.provider_checkout_session_id = p_provider_session_id;

    -- Return a noop when the checkout session does not match any purchase
    if not found then
        return jsonb_build_object('outcome', 'noop');
    end if;

    -- Lock the event, then the tiers, users, offers and purchases in the global order
    select e.*
    into v_event
    from event e
    where e.event_id = v_purchase.event_id
    for update of e;

    perform lock_event_enrollment_rows(v_purchase.event_id, null, v_purchase.user_id);

    -- Lock the purchase before deciding how to reconcile the provider checkout
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.payment_provider_id = p_provider
    and ep.provider_object_account_id = p_provider_object_account_id
    and ep.provider_checkout_session_id = p_provider_session_id
    for update of ep;

    -- Return a noop when the purchase disappeared while waiting for the lock
    if not found then
        return jsonb_build_object('outcome', 'noop');
    end if;

    -- Load the group and linked offer that decide whether the seat can be fulfilled
    select g.*
    into v_group
    from "group" g
    where g.group_id = v_event.group_id;

    -- Load the reservation the purchase claims
    if v_purchase.admission_offer_id is not null then
        select ao.*
        into v_admission_offer
        from admission_offer ao
        where ao.admission_offer_id = v_purchase.admission_offer_id;
    end if;

    -- Derive the fulfilment facts from the locked rows
    v_hold_expired := v_purchase.hold_expires_at is not null
        and v_purchase.hold_expires_at <= current_timestamp;
    v_manually_invited := coalesce(v_admission_offer.source = 'organizer_invitation', false);
    v_provider_payment_reference := coalesce(p_provider_payment_reference, v_purchase.provider_payment_reference);
    v_unfulfillable := not event_accepts_enrollment(v_event, v_group)
        or (
            v_purchase.admission_offer_id is not null
            and (
                v_admission_offer.status <> 'checkout_pending'
                or (
                    v_admission_offer.expires_at is not null
                    and v_admission_offer.expires_at <= current_timestamp
                )
            )
        );

    -- Ignore purchases that are already reconciled
    if not (
        v_purchase.status in ('pending', 'refund-pending')
        or (v_purchase.status = 'expired' and v_hold_expired)
    ) then
        return jsonb_build_object('outcome', 'noop');
    end if;

    -- Validate and persist the authoritative direct-charge amounts before acknowledging payment
    perform validate_direct_charge_checkout_amounts(
        v_purchase,
        p_provider_total_minor,
        p_tax_amount_minor,
        p_provider_application_fee_id
    );
    perform record_direct_charge_checkout_amounts(
        v_purchase,
        p_provider_charge_id,
        p_provider_application_fee_id,
        p_provider_total_minor,
        p_tax_amount_minor
    );

    -- Reserve inventory for paid checkouts that can no longer be fulfilled
    v_requires_refund := v_purchase.status = 'refund-pending'
        or v_hold_expired
        or event_has_pending_refund_recovery(v_purchase.event_id, v_purchase.user_id, v_purchase.event_purchase_id)
        or v_unfulfillable;

    -- Require the payment reference the refund handoff needs
    if v_requires_refund and v_provider_payment_reference is null then
        raise exception 'provider payment reference is required for refund';
    end if;

    -- Persist the refund-pending state before reconciling the queues
    if v_requires_refund and v_purchase.status <> 'refund-pending' then
        perform mark_event_purchase_refund_pending(v_purchase, v_provider_payment_reference);
        v_purchase.status := 'refund-pending';
    end if;

    -- Reconcile due reservations only after paid inventory remains reserved
    perform reconcile_event_enrollment(
        v_purchase.event_id,
        v_purchase.event_ticket_type_id,
        p_provider
    );

    -- Complete active holds even if public registration has closed since checkout started
    if not v_requires_refund then
        -- Complete the linked reservation before creating active attendance
        if v_purchase.admission_offer_id is not null
           and not complete_event_purchase_admission_offer(v_purchase.admission_offer_id) then
            raise exception 'admission offer is no longer available';
        end if;

        -- Persist the completed purchase once the attendee is recorded
        if confirm_event_purchase_attendee(v_purchase.event_id, v_purchase.user_id, v_manually_invited) then
            update event_purchase
            set
                completed_at = current_timestamp,
                hold_expires_at = null,
                provider_payment_reference = v_provider_payment_reference,
                status = 'completed',
                updated_at = current_timestamp
            where event_purchase_id = v_purchase.event_purchase_id;

            -- Return the identifiers needed by downstream notification flows
            return jsonb_build_object(
                'community_id', v_group.community_id,
                'event_id', v_purchase.event_id,
                'outcome', 'completed',
                'user_id', v_purchase.user_id
            );
        end if;
    end if;

    -- Refund purchases that cannot be completed or are awaiting refund retry,
    -- requiring a provider payment reference before the refund handoff
    if v_provider_payment_reference is null then
        raise exception 'provider payment reference is required for refund';
    end if;

    -- Persist the refund-pending state for attendees that could not be confirmed
    if v_purchase.status <> 'refund-pending' then
        perform mark_event_purchase_refund_pending(v_purchase, v_provider_payment_reference);
    end if;

    -- Queue the provider refund for workers before acknowledging the webhook
    v_payment_job_id := enqueue_payment_job(
        'event-purchase-refund',
        p_provider,
        v_purchase.event_purchase_id,
        format('event-purchase-refund-%s', v_purchase.event_purchase_id)
    );

    -- Create the refund only when no durable work exists for the purchase
    if v_payment_job_id is not null then
        insert into event_purchase_refund (
            amount_minor,
            currency_code,
            event_purchase_id,
            kind,
            payment_job_id,
            payment_provider_id,
            status
        ) values (
            p_provider_total_minor,
            v_purchase.currency_code,
            v_purchase.event_purchase_id,
            'automatic-unfulfillable-checkout',
            v_payment_job_id,
            p_provider,
            'provider-pending'
        );
    end if;

    -- Return the queued refund outcome
    return jsonb_build_object('outcome', 'refund_queued');
end;
$$ language plpgsql;
