-- Reconciles a completed provider checkout session with its local purchase.
create or replace function reconcile_event_purchase_for_checkout_session(
    p_provider text,
    p_provider_session_id text,
    p_provider_payment_reference text
)
returns jsonb as $$
declare
    v_admission_offer_id uuid;
    v_amount_minor bigint;
    v_community_id uuid;
    v_currency_code text;
    v_event_discount_code_id uuid;
    v_event_id uuid;
    v_event_ticket_type_id uuid;
    v_hold_expired boolean;
    v_lock_user_id uuid;
    v_manually_invited boolean;
    v_provider_payment_reference text;
    v_purchase_id uuid;
    v_recovery_pending boolean;
    v_requires_refund boolean;
    v_status text;
    v_unfulfillable boolean;
    v_user_id uuid;
begin
    -- Resolve immutable enrollment identifiers before taking lifecycle locks
    select
        ep.admission_offer_id,
        ep.event_id,
        ep.event_ticket_type_id,
        ep.user_id
    into
        v_admission_offer_id,
        v_event_id,
        v_event_ticket_type_id,
        v_user_id
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

    -- Lock ticket tiers before the enrollment rows used by reconciliation
    perform 1
    from event_ticket_type ett
    where ett.event_id = v_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Acquire affected event-user locks in stable order
    for v_lock_user_id in
        select affected_user.user_id
        from (
            select ao.user_id
            from admission_offer ao
            where ao.event_id = v_event_id
            and ao.status in ('checkout_pending', 'pending')

            union

            select ep.user_id
            from event_purchase ep
            where ep.event_id = v_event_id
            and ep.status = 'pending'

            union

            select ew.user_id
            from event_waitlist ew
            where ew.event_id = v_event_id

            union

            select v_user_id
        ) affected_user
        order by affected_user.user_id
    loop
        perform pg_advisory_xact_lock(
            hashtext(v_event_id::text),
            hashtext(v_lock_user_id::text)
        );
    end loop;

    -- Lock active offers and pending purchases in stable identifier order
    perform 1
    from admission_offer ao
    where ao.event_id = v_event_id
    and ao.status in ('checkout_pending', 'pending')
    order by ao.admission_offer_id
    for update of ao;

    perform 1
    from event_purchase ep
    where ep.event_id = v_event_id
    and ep.status = 'pending'
    order by ep.event_purchase_id
    for update of ep;

    -- Lock the purchase before deciding how to reconcile the provider checkout
    select
        ep.admission_offer_id,
        ep.amount_minor,
        g.community_id,
        ep.currency_code,
        ep.event_discount_code_id,
        ep.event_id,
        ep.hold_expires_at is not null
            and ep.hold_expires_at <= current_timestamp,
        coalesce(ao.source = 'organizer_invitation', false),
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
            )
            or (
                ep.admission_offer_id is not null
                and (
                    ao.status <> 'checkout_pending'
                    or (
                        ao.expires_at is not null
                        and ao.expires_at <= current_timestamp
                    )
                )
            ),
        ep.user_id
    into
        v_admission_offer_id,
        v_amount_minor,
        v_community_id,
        v_currency_code,
        v_event_discount_code_id,
        v_event_id,
        v_hold_expired,
        v_manually_invited,
        v_provider_payment_reference,
        v_purchase_id,
        v_recovery_pending,
        v_status,
        v_unfulfillable,
        v_user_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    left join admission_offer ao
        on ao.admission_offer_id = ep.admission_offer_id
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

    -- Reserve inventory for paid checkouts that can no longer be fulfilled
    v_requires_refund := v_status = 'refund-pending'
        or v_hold_expired
        or v_recovery_pending
        or v_unfulfillable;

    if v_requires_refund and v_provider_payment_reference is null then
        raise exception 'provider payment reference is required for refund';
    end if;

    if v_requires_refund and v_status <> 'refund-pending' then
        update event_purchase
        set
            hold_expires_at = null,
            provider_payment_reference = v_provider_payment_reference,
            status = 'refund-pending',
            updated_at = current_timestamp
        where event_purchase_id = v_purchase_id;

        if v_status = 'pending' and v_event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_event_discount_code_id);
        end if;

        perform release_event_checkout_attendee_hold(v_event_id, v_user_id);
        v_status := 'refund-pending';
    end if;

    -- Reconcile due reservations only after paid inventory remains reserved
    perform reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_provider
    );

    -- Complete active holds even if public registration has closed since checkout started
    if not v_requires_refund then
        -- Complete the linked reservation before creating active attendance
        if v_admission_offer_id is not null then
            update admission_offer
            set
                status = 'completed',
                updated_at = current_timestamp
            where admission_offer_id = v_admission_offer_id
            and status = 'checkout_pending';

            if not found then
                raise exception 'admission offer is no longer available';
            end if;
        end if;

        -- Add the attendee, reviving only checkout-compatible states
        insert into event_attendee (event_id, user_id, manually_invited)
        values (v_event_id, v_user_id, v_manually_invited)
        on conflict (event_id, user_id) do update
        set
            attendance_canceled_at = null,
            attendance_canceled_by_user_id = null,
            manually_invited = excluded.manually_invited,
            status = 'confirmed'
        where event_attendee.status in (
            'attendance-canceled',
            'confirmed',
            'invitation-canceled',
            'registration-questions-pending'
        );

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

    -- Queue the provider refund for workers before acknowledging the webhook
    insert into event_purchase_refund (
        amount_minor,
        currency_code,
        event_purchase_id,
        idempotency_key,
        kind,
        payment_provider_id,
        status
    ) values (
        v_amount_minor,
        v_currency_code,
        v_purchase_id,
        format('event-purchase-refund-%s', v_purchase_id),
        'automatic-unfulfillable-checkout',
        p_provider,
        'provider-pending'
    )
    on conflict (event_purchase_id) do nothing;

    return jsonb_build_object('outcome', 'refund_queued');
end;
$$ language plpgsql;
