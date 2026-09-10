-- Reuses an active purchase or creates a pending checkout hold.
create or replace function prepare_event_checkout_purchase(
    p_community_id uuid,
    p_event_id uuid,
    p_event_ticket_type_id uuid,
    p_user_id uuid,
    p_discount_code text,
    p_configured_provider text,
    p_registration_answers jsonb default null,
    p_admission_offer_id uuid default null,
    p_platform_fee_bps int default 0
)
returns jsonb as $$
declare
    v_admission_offer admission_offer;
    v_cached_performance_location_fingerprint text;
    v_cached_product_fingerprint text;
    v_cached_provider_tax_location_id text;
    v_cached_provider_tax_product_id text;
    v_charge_model text;
    v_community community;
    v_context record;
    v_currency_code text;
    v_discount_amount_minor bigint;
    v_event event;
    v_event_discount_code_id uuid;
    v_existing_purchase record;
    v_final_amount_minor bigint;
    v_group "group";
    v_hold_expires_at timestamptz := current_timestamp + interval '15 minutes';
    v_is_external_paid boolean := false;
    v_normalized_discount_code text := upper(nullif(btrim(p_discount_code), ''));
    v_offer_pricing record;
    v_purchase_id uuid;
    v_recipient jsonb;
    v_route_summary jsonb;
    v_seller_snapshot jsonb;
    v_theme jsonb;
    v_ticket_title text;
    v_use_offer_snapshot boolean := false;
    v_venue_snapshot jsonb;
    v_window_hours int;
begin
    -- Reject platform fee configuration outside the valid basis-point range
    if p_platform_fee_bps is null or p_platform_fee_bps < 0 or p_platform_fee_bps >= 10000 then
        raise exception 'platform fee basis points must be between 0 and 9999';
    end if;

    -- Lock the event first to keep a consistent event -> purchase -> attendee
    -- lock order with attend_event, then validate its current state
    v_event := prepare_event_checkout_validate_event(p_community_id, p_event_id);
    v_currency_code := v_event.payment_currency_code;

    -- Report stale ticket selections before reconciliation scopes to the tier
    if not exists (
        select 1
        from event_ticket_type ett
        where ett.event_id = p_event_id
        and ett.event_ticket_type_id = p_event_ticket_type_id
    ) then
        return jsonb_build_object('conflict', 'ticket-type-unavailable');
    end if;

    -- Reconcile the selected tier before direct checkout can reserve capacity
    perform reconcile_event_enrollment(
        p_event_id,
        p_event_ticket_type_id,
        p_configured_provider
    );

    -- Serialize this attendee after the event and ticket-tier locks
    perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(p_user_id::text));

    -- Load the group and community details needed by the checkout provider
    select *
    into v_context
    from load_checkout_context(p_event_id);
    v_community := v_context.community_row;
    v_group := v_context.group_row;
    v_recipient := v_group.payment_recipient;
    v_venue_snapshot := event_venue_snapshot(v_event);
    v_route_summary := jsonb_build_object(
        'community_display_name', v_community.display_name,
        'community_name', v_community.name,
        'event_id', p_event_id,
        'event_name', v_event.name,
        'event_slug', v_event.slug,
        'event_starts_at', epoch_seconds(v_event.starts_at),
        'event_timezone', v_event.timezone,
        'group_name', v_group.name,
        'group_slug', v_group.slug,
        'group_slug_pretty', v_group.slug_pretty
    );

    -- Lock and validate the owned offer before selecting or reusing a purchase
    if p_admission_offer_id is not null then
        select ao.*
        into v_admission_offer
        from admission_offer ao
        where ao.admission_offer_id = p_admission_offer_id
        and ao.event_id = p_event_id
        and ao.event_ticket_type_id = p_event_ticket_type_id
        and ao.user_id = p_user_id
        for update of ao;

        -- Reject missing, inactive, or expired admission offers
        if not found
           or not admission_offer_is_active(v_admission_offer.status)
           or (
                v_admission_offer.expires_at is not null
                and v_admission_offer.expires_at <= current_timestamp
           ) then
            return jsonb_build_object('conflict', 'admission-offer-unavailable');
        end if;

        -- Freeze in-progress holds and prior discounted claims
        v_use_offer_snapshot :=
            v_admission_offer.amount_minor is not null
            and (
                v_admission_offer.status = 'checkout_pending'
                or v_admission_offer.discount_code is not null
            );

        -- Honor the immutable pricing snapshot for frozen offer claims
        if v_use_offer_snapshot then
            select *
            into v_offer_pricing
            from prepare_event_checkout_resolve_offer_pricing(v_admission_offer, v_normalized_discount_code);

            -- Reject attempts to replace the snapshotted discount code
            if v_offer_pricing.price_locked then
                return jsonb_build_object('conflict', 'admission-offer-price-locked');
            end if;

            -- Omitted codes reuse the immutable offer pricing snapshot
            v_normalized_discount_code := v_offer_pricing.discount_code;
        end if;
    end if;

    -- Require direct callers to claim an active owned admission offer explicitly
    if p_admission_offer_id is null and exists (
        select 1
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and admission_offer_is_active(ao.status)
        and ao.expires_at > current_timestamp
    ) then
        return jsonb_build_object('conflict', 'admission-offer-required');
    end if;

    -- Reuse an equivalent purchase or return an active completed purchase
    select *
    into v_existing_purchase
    from prepare_event_checkout_find_existing_purchase(
        p_event_id,
        p_event_ticket_type_id,
        p_user_id,
        v_normalized_discount_code,
        p_admission_offer_id
    );

    -- Return completed or selection-compatible purchases without replacing them
    if found
       and (
            v_existing_purchase.status <> 'pending'
            or v_existing_purchase.matches_selection
       ) then
        -- Refresh questionnaire answers before returning a reused pending checkout
        if v_existing_purchase.status = 'pending' then
            -- Reject attendee states that checkout completion cannot confirm
            perform prepare_event_checkout_validate_attendee_state(p_event_id, p_user_id);

            perform upsert_pending_registration_answers(
                p_event_id,
                p_user_id,
                v_event.registration_questions,
                p_registration_answers
            );
        end if;

        return prepare_event_checkout_get_purchase_summary(v_existing_purchase.event_purchase_id)
            || v_route_summary;
    end if;

    -- Reject new or replacement checkout holds outside the registration window
    if p_admission_offer_id is null
       and not is_registration_window_open(
            v_event.registration_starts_at,
            v_event.registration_ends_at,
            v_event.starts_at
        ) then
        raise exception 'event registration is not open' using errcode = 'OCG01';
    end if;

    -- Use the immutable snapshot for a frozen offer claim
    if v_use_offer_snapshot then
        v_currency_code := v_offer_pricing.currency_code;
        v_discount_amount_minor := v_offer_pricing.discount_amount_minor;
        v_event_discount_code_id := v_offer_pricing.event_discount_code_id;
        v_final_amount_minor := v_offer_pricing.final_amount_minor;
        v_ticket_title := v_offer_pricing.ticket_title;

    -- Resolve current ticket pricing for pending offers and direct checkout,
    -- translating expected failures into stable conflicts without rolling
    -- back the queue reconciliation
    else
        begin
            select
                discount_amount_minor,
                event_discount_code_id,
                final_amount_minor,
                ticket_title
            into
                v_discount_amount_minor,
                v_event_discount_code_id,
                v_final_amount_minor,
                v_ticket_title
            from prepare_event_checkout_validate_and_resolve_pricing(
                p_event_id,
                p_event_ticket_type_id,
                p_user_id,
                v_normalized_discount_code,
                p_admission_offer_id
            );
        exception
            -- Translate expected pricing failures into stable conflict results
            when sqlstate 'OCG01' then
                -- Report admission offers that became unavailable
                if sqlerrm = 'admission offer is no longer available' then
                    return jsonb_build_object('conflict', 'admission-offer-unavailable');
                -- Fall back to a stored offer snapshot when live pricing is gone
                elsif sqlerrm = 'ticket type does not have an active price window' then
                    -- Report ticket types without an active price or stored snapshot
                    if p_admission_offer_id is null
                       or v_admission_offer.amount_minor is null
                       or v_admission_offer.source not in ('approval', 'organizer_invitation') then
                        return jsonb_build_object('conflict', 'ticket-type-price-unavailable');
                    end if;

                    -- Use stored approval and organizer-invitation snapshots
                    select *
                    into v_offer_pricing
                    from prepare_event_checkout_resolve_offer_pricing(v_admission_offer, v_normalized_discount_code);

                    -- Reject attempts to replace the snapshotted discount code
                    if v_offer_pricing.price_locked then
                        return jsonb_build_object('conflict', 'admission-offer-price-locked');
                    end if;

                    v_currency_code := v_offer_pricing.currency_code;
                    v_discount_amount_minor := v_offer_pricing.discount_amount_minor;
                    v_event_discount_code_id := v_offer_pricing.event_discount_code_id;
                    v_final_amount_minor := v_offer_pricing.final_amount_minor;
                    v_normalized_discount_code := v_offer_pricing.discount_code;
                    v_ticket_title := v_offer_pricing.ticket_title;
                -- Report inactive ticket types
                elsif sqlerrm = 'ticket type is not active' then
                    return jsonb_build_object('conflict', 'ticket-type-inactive');
                -- Report ticket types unavailable through direct checkout
                elsif sqlerrm in (
                    'ticket type is not available for direct checkout',
                    'ticket type not found'
                ) then
                    return jsonb_build_object('conflict', 'ticket-type-unavailable');
                -- Report exhausted ticket inventory and queued-user priority over direct checkout
                elsif sqlerrm in ('ticket type is sold out', 'ticket type has queued users') then
                    return jsonb_build_object('conflict', 'ticket-type-sold-out');
                -- Propagate unexpected pricing failures
                else
                    raise;
                end if;
        end;
    end if;

    -- Require payment configuration only when the final amount needs a provider
    if v_final_amount_minor > 0 then
        -- Never fall through to Stripe for events marked with an external payment URL
        if v_event.external_payment_url is not null then
            -- Reject new external holds when the group is no longer eligible
            if not is_event_external_payments_ready(p_event_id) then
                return jsonb_build_object('conflict', 'payment-setup-unavailable');
            end if;

            v_is_external_paid := true;
            v_charge_model := 'external';
            perform validate_payment_amount(v_currency_code, v_final_amount_minor);

            -- Compute the organizer-confirmation deadline once at hold creation
            select least(
                coalesce(v_event.external_payment_window_hours, cfg.default_payment_window_hours),
                cfg.max_payment_window_hours
            )
            into v_window_hours
            from external_payments_config cfg
            where cfg.singleton;

            -- Reject missing window configuration after the eligibility check
            if not found or v_window_hours is null then
                return jsonb_build_object('conflict', 'payment-setup-unavailable');
            end if;

            v_hold_expires_at := least(
                current_timestamp + make_interval(hours => v_window_hours),
                case
                    -- Cap direct checkout by the public registration window
                    when p_admission_offer_id is null then
                        coalesce(v_event.registration_ends_at, 'infinity'::timestamptz)
                    -- Invitation and approval claims skip the public registration window
                    else 'infinity'::timestamptz
                end,
                coalesce(v_event.starts_at, 'infinity'::timestamptz)
            );

            -- Reject holds that would expire immediately
            if v_hold_expires_at <= current_timestamp then
                return jsonb_build_object('conflict', 'payment-window-unavailable');
            end if;

        -- Translate Stripe readiness failures into a stable checkout conflict
        else
            begin
                perform validate_event_ticketing_payment_readiness(
                    p_configured_provider,
                    true,
                    v_currency_code,
                    v_recipient,
                    p_event_id
                );
            exception
                -- Hide provider-readiness details behind the stable checkout conflict
                when sqlstate 'OCG01' then
                    return jsonb_build_object('conflict', 'payment-setup-unavailable');
            end;
            perform validate_payment_amount(v_currency_code, v_final_amount_minor);
            v_charge_model := 'direct-charge';
        end if;
    -- Retain the configured currency for discounted-to-zero purchases
    elsif v_discount_amount_minor > 0 then
        v_charge_model := 'ocg-free';

        -- Discounted-to-zero purchases retain the event currency snapshot
        if v_currency_code is null then
            return jsonb_build_object('conflict', 'payment-setup-unavailable');
        end if;

        -- Validate the retained currency independently of provider readiness
        begin
            perform validate_payment_currency_code(v_currency_code);
        exception
            -- Hide unsupported currency details behind the stable checkout conflict
            when sqlstate 'OCG01' then
                return jsonb_build_object('conflict', 'payment-setup-unavailable');
        end;
    -- Remove payment configuration from intrinsically free purchases
    else
        v_charge_model := 'ocg-free';
        v_currency_code := null;
        v_recipient := null;
    end if;

    -- Snapshot the immutable seller and reuse cached automatic-tax resources for Stripe purchases
    if v_charge_model = 'direct-charge' then
        v_seller_snapshot := jsonb_build_object(
            'connected_account_id', v_recipient->>'recipient_id',
            'display_name', v_recipient->>'seller_display_name',
            'provider', v_recipient->>'provider'
        );

        -- Reuse immutable automatic-tax resources within the seller account
        if v_event.tax_calculation_mode = 'automatic' then
            select *
            into
                v_cached_performance_location_fingerprint,
                v_cached_product_fingerprint,
                v_cached_provider_tax_location_id,
                v_cached_provider_tax_product_id
            from prepare_event_checkout_lookup_tax_cache(
                p_configured_provider,
                v_recipient->>'recipient_id',
                v_venue_snapshot,
                v_ticket_title
            );
        end if;
    end if;

    -- Release any replaced pending selection before creating the new hold
    if v_existing_purchase.event_purchase_id is not null and v_existing_purchase.status = 'pending' then
        perform prepare_event_checkout_expire_previous_hold(v_existing_purchase.event_purchase_id);
    end if;

    -- Snapshot the pending offer claim and move its reservation into checkout
    if p_admission_offer_id is not null then
        -- Keep the 15-minute Stripe hold from outliving a shorter offer deadline
        if not v_is_external_paid then
            v_hold_expires_at := least(
                v_hold_expires_at,
                coalesce(v_admission_offer.expires_at, 'infinity'::timestamptz)
            );
        end if;

        -- Replace the issue snapshot with the claimed price on first checkout
        if v_admission_offer.status = 'pending' then
            update admission_offer
            set
                amount_minor = v_final_amount_minor,
                currency_code = v_currency_code,
                discount_amount_minor = v_discount_amount_minor,
                discount_code = v_normalized_discount_code,
                event_discount_code_id = v_event_discount_code_id,
                expires_at = case
                    -- Raise the offer deadline so it cannot truncate an external hold
                    when v_is_external_paid
                    then greatest(expires_at, v_hold_expires_at)
                    -- Preserve the original offer deadline for Stripe checkouts
                    else expires_at
                end,
                status = 'checkout_pending',
                ticket_title = v_ticket_title,
                updated_at = current_timestamp
            where admission_offer_id = p_admission_offer_id
            and status = 'pending';

        -- Keep the frozen snapshot on checkout retries
        else
            update admission_offer
            set
                expires_at = case
                    -- Raise the offer deadline so it cannot truncate an external hold
                    when v_is_external_paid
                    then greatest(expires_at, v_hold_expires_at)
                    -- Preserve the original offer deadline for Stripe checkouts
                    else expires_at
                end,
                status = 'checkout_pending',
                updated_at = current_timestamp
            where admission_offer_id = p_admission_offer_id
            and status = 'checkout_pending';
        end if;

        -- Reject offers that became unavailable before reservation
        if not found then
            return jsonb_build_object('conflict', 'admission-offer-unavailable');
        end if;
    end if;

    -- Persist questionnaire answers before checkout starts so completion can confirm the row
    perform upsert_pending_registration_answers(
        p_event_id,
        p_user_id,
        v_event.registration_questions,
        p_registration_answers
    );

    -- Reserve the chosen discount usage for the new pending purchase
    if v_event_discount_code_id is not null then
        perform prepare_event_checkout_reserve_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Insert the new pending purchase, snapshotting provider settings for
    -- Stripe purchases only and deducting the platform fee (rounded down)
    -- from the group's proceeds
    insert into event_purchase (
        admission_offer_id,
        amount_minor,
        charge_model,
        connected_seller_id,
        currency_code,
        discount_amount_minor,
        discount_code,
        event_discount_code_id,
        event_id,
        event_ticket_type_id,
        hold_expires_at,
        manual_tax_rate_ids,
        payment_provider_id,
        platform_fee_bps,
        provider_object_account_id,
        provider_tax_code,
        provisional_platform_fee_amount_minor,
        seller_snapshot,
        status,
        tax_behavior,
        tax_calculation_mode,
        tax_classification,
        ticket_title,
        user_id,
        venue_snapshot
    ) values (
        p_admission_offer_id,
        v_final_amount_minor,
        v_charge_model,
        case
            -- Snapshot the connected seller for Stripe purchases
            when v_charge_model = 'direct-charge' then v_recipient->>'recipient_id'
        end,
        v_currency_code,
        v_discount_amount_minor,
        v_normalized_discount_code,
        v_event_discount_code_id,
        p_event_id,
        p_event_ticket_type_id,
        v_hold_expires_at,
        case
            -- Snapshot manual Tax Rate identifiers for Stripe purchases
            when v_charge_model = 'direct-charge' then v_event.manual_tax_rate_ids
        end,
        case
            -- Snapshot the payment provider for Stripe purchases
            when v_charge_model = 'direct-charge' then p_configured_provider
        end,
        case
            -- External purchases never collect a platform fee
            when v_is_external_paid then 0
            -- Stripe purchases persist the configured basis-point fee
            else p_platform_fee_bps
        end,
        case
            -- Bind provider objects to the connected seller for Stripe purchases
            when v_charge_model = 'direct-charge' then v_recipient->>'recipient_id'
        end,
        case
            -- Classify automatic-tax Stripe purchases as professional event admission
            when v_charge_model = 'direct-charge' and v_event.tax_calculation_mode = 'automatic'
                then 'txcd_50013001'
        end,
        case
            -- External purchases never collect a platform fee
            when v_is_external_paid then 0
            -- Stripe purchases apply the configured basis-point fee
            else (v_final_amount_minor * p_platform_fee_bps) / 10000
        end,
        v_seller_snapshot,
        'pending',
        case
            -- Snapshot the tax display behavior for Stripe purchases
            when v_charge_model = 'direct-charge' then v_event.tax_behavior
        end,
        case
            -- Snapshot the tax calculation mode for Stripe purchases
            when v_charge_model = 'direct-charge' then v_event.tax_calculation_mode
        end,
        case
            -- Snapshot the admission tax classification for Stripe purchases
            when v_charge_model = 'direct-charge' then 'professional-event-admission'
        end,
        v_ticket_title,
        p_user_id,
        case
            -- Snapshot the taxable venue for Stripe purchases
            when v_charge_model = 'direct-charge' then v_venue_snapshot
        end
    )
    returning event_purchase_id into v_purchase_id;

    -- Enqueue pending-payment instructions only when a new external hold is created
    if v_is_external_paid then
        select s.theme
        into v_theme
        from site s
        limit 1;

        perform enqueue_notification(
            'event-external-payment-pending',
            jsonb_strip_nulls(jsonb_build_object(
                'amount_minor', v_final_amount_minor,
                'currency_code', v_currency_code,
                'dashboard_url', '/dashboard/user?tab=events',
                'deadline', epoch_seconds(v_hold_expires_at),
                'event_id', p_event_id,
                'event_name', v_event.name,
                'event_purchase_id', v_purchase_id,
                'external_payment_instructions', v_event.external_payment_instructions,
                'external_payment_url', v_event.external_payment_url,
                'group_name', v_group.name,
                'theme', v_theme,
                'ticket_title', v_ticket_title,
                'timezone', v_event.timezone
            )),
            '[]'::jsonb,
            array[p_user_id]
        );
    end if;

    -- Return the pending purchase summary used by the checkout flow
    return prepare_event_checkout_get_purchase_summary(v_purchase_id)
        || v_route_summary
        || jsonb_strip_nulls(jsonb_build_object(
            'cached_performance_location_fingerprint', v_cached_performance_location_fingerprint,
            'cached_product_fingerprint', v_cached_product_fingerprint,
            'cached_provider_tax_location_id', v_cached_provider_tax_location_id,
            'cached_provider_tax_product_id', v_cached_provider_tax_product_id
        ));
end;
$$ language plpgsql;
