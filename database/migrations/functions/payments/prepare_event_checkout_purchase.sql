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
    v_admission_offer_expires_at timestamptz;
    v_admission_offer_snapshot_amount_minor bigint;
    v_admission_offer_snapshot_currency_code text;
    v_admission_offer_snapshot_discount_amount_minor bigint;
    v_admission_offer_snapshot_discount_code text;
    v_admission_offer_snapshot_event_discount_code_id uuid;
    v_admission_offer_snapshot_ticket_title text;
    v_admission_offer_source text;
    v_admission_offer_status text;
    v_cached_performance_location_fingerprint text;
    v_cached_product_fingerprint text;
    v_cached_provider_tax_location_id text;
    v_cached_provider_tax_product_id text;
    v_charge_model text;
    v_community_display_name text;
    v_community_name text;
    v_currency_code text;
    v_discount_amount_minor bigint;
    v_event_discount_code_id uuid;
    v_event_external_payment_instructions text;
    v_event_external_payment_url text;
    v_event_external_payment_window_hours int;
    v_event_name text;
    v_event_registration_ends_at timestamptz;
    v_event_registration_starts_at timestamptz;
    v_event_slug text;
    v_event_starts_at timestamptz;
    v_event_timezone text;
    v_existing_purchase_id uuid;
    v_existing_purchase_matches_selection boolean;
    v_existing_purchase_status text;
    v_final_amount_minor bigint;
    v_group_name text;
    v_group_slug text;
    v_group_slug_pretty text;
    v_hold_expires_at timestamptz := current_timestamp + interval '15 minutes';
    v_is_external_paid boolean := false;
    v_manual_tax_rate_ids text[];
    v_normalized_discount_code text := upper(nullif(btrim(p_discount_code), ''));
    v_provisional_platform_fee_amount_minor bigint;
    v_purchase_id uuid;
    v_recipient jsonb;
    v_registration_questions jsonb;
    v_seller_snapshot jsonb;
    v_tax_behavior text;
    v_tax_calculation_mode text;
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
    v_currency_code := prepare_event_checkout_validate_event(
        p_community_id,
        p_event_id
    );

    -- Reconcile the selected tier before direct checkout can reserve capacity
    perform reconcile_event_enrollment(
        p_event_id,
        p_event_ticket_type_id,
        p_configured_provider
    );

    -- Serialize this attendee after the event and ticket-tier locks
    perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(p_user_id::text));

    -- Load the route and recipient details needed by the checkout provider
    select
        c.display_name,
        c.name,
        e.external_payment_instructions,
        e.external_payment_url,
        e.external_payment_window_hours,
        e.manual_tax_rate_ids,
        e.name,
        e.registration_ends_at,
        e.registration_questions,
        e.registration_starts_at,
        e.slug,
        e.starts_at,
        e.tax_behavior,
        e.tax_calculation_mode,
        e.timezone,
        jsonb_build_object(
            'address', nullif(btrim(e.venue_address), ''),
            'city', nullif(btrim(e.venue_city), ''),
            'country_code', nullif(btrim(e.venue_country_code), ''),
            'name', nullif(btrim(e.venue_name), ''),
            'state_code', nullif(btrim(e.venue_state_code), ''),
            'state_name', nullif(btrim(e.venue_state_name), ''),
            'zip_code', nullif(btrim(e.venue_zip_code), '')
        ),
        g.name,
        g.slug,
        g.slug_pretty,
        g.payment_recipient
    into
        v_community_display_name,
        v_community_name,
        v_event_external_payment_instructions,
        v_event_external_payment_url,
        v_event_external_payment_window_hours,
        v_manual_tax_rate_ids,
        v_event_name,
        v_event_registration_ends_at,
        v_registration_questions,
        v_event_registration_starts_at,
        v_event_slug,
        v_event_starts_at,
        v_tax_behavior,
        v_tax_calculation_mode,
        v_event_timezone,
        v_venue_snapshot,
        v_group_name,
        v_group_slug,
        v_group_slug_pretty,
        v_recipient
    from event e
    join "group" g on g.group_id = e.group_id
    join community c on c.community_id = g.community_id
    where e.event_id = p_event_id
    and g.community_id = p_community_id;

    -- Lock and validate the owned offer before selecting or reusing a purchase
    if p_admission_offer_id is not null then
        select
            ao.amount_minor,
            ao.currency_code,
            ao.discount_amount_minor,
            ao.discount_code,
            ao.event_discount_code_id,
            ao.expires_at,
            ao.source,
            ao.status,
            ao.ticket_title
        into
            v_admission_offer_snapshot_amount_minor,
            v_admission_offer_snapshot_currency_code,
            v_admission_offer_snapshot_discount_amount_minor,
            v_admission_offer_snapshot_discount_code,
            v_admission_offer_snapshot_event_discount_code_id,
            v_admission_offer_expires_at,
            v_admission_offer_source,
            v_admission_offer_status,
            v_admission_offer_snapshot_ticket_title
        from admission_offer ao
        where ao.admission_offer_id = p_admission_offer_id
        and ao.event_id = p_event_id
        and ao.event_ticket_type_id = p_event_ticket_type_id
        and ao.user_id = p_user_id
        for update of ao;

        -- Reject missing, inactive, or expired admission offers
        if not found
           or v_admission_offer_status not in ('checkout_pending', 'pending')
           or (
                v_admission_offer_expires_at is not null
                and v_admission_offer_expires_at <= current_timestamp
           ) then
            return jsonb_build_object('conflict', 'admission-offer-unavailable');
        end if;

        -- Freeze in-progress holds and prior discounted claims
        v_use_offer_snapshot :=
            v_admission_offer_snapshot_amount_minor is not null
            and (
                v_admission_offer_status = 'checkout_pending'
                or v_admission_offer_snapshot_discount_code is not null
            );

        -- Honor the immutable pricing snapshot for frozen offer claims
        if v_use_offer_snapshot then
            -- Reject attempts to replace the snapshotted discount code
            if v_normalized_discount_code is not null
               and upper(nullif(btrim(v_admission_offer_snapshot_discount_code), ''))
                   is distinct from v_normalized_discount_code then
                return jsonb_build_object(
                    'conflict',
                    'admission-offer-price-locked'
                );
            end if;

            -- Omitted codes reuse the immutable offer pricing snapshot
            v_normalized_discount_code := upper(
                nullif(btrim(v_admission_offer_snapshot_discount_code), '')
            );
        end if;
    end if;

    -- Require direct callers to claim an active owned admission offer explicitly
    if p_admission_offer_id is null and exists (
        select 1
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and ao.status in ('checkout_pending', 'pending')
        and ao.expires_at > current_timestamp
    ) then
        return jsonb_build_object('conflict', 'admission-offer-required');
    end if;

    -- Reuse an equivalent purchase or return an active completed purchase
    select
        event_purchase_id,
        matches_selection,
        status
    into
        v_existing_purchase_id,
        v_existing_purchase_matches_selection,
        v_existing_purchase_status
    from prepare_event_checkout_find_existing_purchase(
        p_event_id,
        p_event_ticket_type_id,
        p_user_id,
        v_normalized_discount_code,
        p_admission_offer_id
    );

    -- Return completed or selection-compatible purchases without replacing them
    if found then
        -- Reuse terminal purchases or pending purchases with the same selection
        if v_existing_purchase_status <> 'pending'
           or v_existing_purchase_matches_selection then
            -- Refresh questionnaire answers before returning a reused pending checkout
            if v_existing_purchase_status = 'pending' then
                -- Reject attendee states that checkout completion cannot confirm
                perform prepare_event_checkout_validate_attendee_state(p_event_id, p_user_id);

                perform upsert_pending_registration_answers(
                    p_event_id,
                    p_user_id,
                    v_registration_questions,
                    p_registration_answers
                );
            end if;

            return prepare_event_checkout_get_purchase_summary(v_existing_purchase_id)
                || jsonb_build_object(
                    'community_display_name', v_community_display_name,
                    'community_name', v_community_name,
                    'event_id', p_event_id,
                    'event_name', v_event_name,
                    'event_slug', v_event_slug,
                    'event_starts_at', extract(epoch from v_event_starts_at)::bigint,
                    'event_timezone', v_event_timezone,
                    'group_name', v_group_name,
                    'group_slug', v_group_slug,
                    'group_slug_pretty', v_group_slug_pretty
                );
        end if;
    end if;

    -- Reject new or replacement checkout holds outside the registration window
    if p_admission_offer_id is null
       and not is_registration_window_open(
            v_event_registration_starts_at,
            v_event_registration_ends_at,
            v_event_starts_at
        ) then
        raise exception 'event registration is not open';
    end if;

    -- Resolve pricing without rolling back queue reconciliation on sold-out conflicts
    -- Use the immutable snapshot for a frozen offer claim
    if v_use_offer_snapshot then
        v_currency_code := v_admission_offer_snapshot_currency_code;
        v_discount_amount_minor := v_admission_offer_snapshot_discount_amount_minor;
        v_event_discount_code_id := v_admission_offer_snapshot_event_discount_code_id;
        v_final_amount_minor := v_admission_offer_snapshot_amount_minor;
        v_ticket_title := v_admission_offer_snapshot_ticket_title;
    -- Resolve current ticket pricing for pending offers and direct checkout
    else
        -- Translate live pricing outcomes into stable checkout conflicts
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
            when raise_exception then
                -- Report admission offers that became unavailable
                if sqlerrm = 'admission offer is no longer available' then
                    return jsonb_build_object('conflict', 'admission-offer-unavailable');
                -- Fall back to a stored offer snapshot when live pricing is gone
                elsif sqlerrm = 'ticket type does not have an active price window' then
                    -- Use stored approval and organizer-invitation snapshots
                    if p_admission_offer_id is not null
                       and v_admission_offer_snapshot_amount_minor is not null
                       and v_admission_offer_source in (
                            'approval',
                            'organizer_invitation'
                       ) then
                        -- Reject attempts to replace the snapshotted discount code
                        if v_normalized_discount_code is not null
                           and upper(
                                nullif(
                                    btrim(v_admission_offer_snapshot_discount_code),
                                    ''
                                )
                           ) is distinct from v_normalized_discount_code then
                            return jsonb_build_object(
                                'conflict',
                                'admission-offer-price-locked'
                            );
                        end if;

                        -- Omitted codes reuse the stored offer pricing snapshot
                        v_normalized_discount_code := upper(
                            nullif(
                                btrim(v_admission_offer_snapshot_discount_code),
                                ''
                            )
                        );
                        v_currency_code := v_admission_offer_snapshot_currency_code;
                        v_discount_amount_minor :=
                            v_admission_offer_snapshot_discount_amount_minor;
                        v_event_discount_code_id :=
                            v_admission_offer_snapshot_event_discount_code_id;
                        v_final_amount_minor := v_admission_offer_snapshot_amount_minor;
                        v_ticket_title := v_admission_offer_snapshot_ticket_title;
                    -- Report ticket types without an active price or stored snapshot
                    else
                        return jsonb_build_object(
                            'conflict',
                            'ticket-type-price-unavailable'
                        );
                    end if;
                -- Report inactive ticket types
                elsif sqlerrm = 'ticket type is not active' then
                    return jsonb_build_object('conflict', 'ticket-type-inactive');
                -- Report ticket types unavailable through direct checkout
                elsif sqlerrm in (
                    'ticket type is not available for direct checkout',
                    'ticket type not found'
                ) then
                    return jsonb_build_object('conflict', 'ticket-type-unavailable');
                -- Report exhausted ticket inventory
                elsif sqlerrm = 'ticket type is sold out' then
                    return jsonb_build_object('conflict', 'ticket-type-sold-out');
                -- Preserve queued-user priority over direct checkout
                elsif sqlerrm = 'ticket type has queued users' then
                    return jsonb_build_object('conflict', 'ticket-type-sold-out');
                end if;

                -- Propagate unexpected pricing failures after the known conflicts
                if sqlerrm <> 'ticket type does not have an active price window'
                   or p_admission_offer_id is null
                   or v_admission_offer_snapshot_amount_minor is null
                   or v_admission_offer_source not in (
                        'approval',
                        'organizer_invitation'
                   ) then
                    raise;
                end if;
        end;
    end if;

    -- Require payment configuration only when the final amount needs a provider
    if v_final_amount_minor > 0 then
        -- Never fall through to Stripe for events marked with an external payment URL
        if v_event_external_payment_url is not null then
            -- Reject new external holds when the group is no longer eligible
            if not is_event_external_payments_ready(p_event_id) then
                return jsonb_build_object('conflict', 'payment-setup-unavailable');
            end if;

            v_is_external_paid := true;
            v_charge_model := 'external';
            perform validate_payment_amount(v_currency_code, v_final_amount_minor);

            -- Compute the organizer-confirmation deadline once at hold creation
            select least(
                coalesce(v_event_external_payment_window_hours, cfg.default_payment_window_hours),
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
                        coalesce(v_event_registration_ends_at, 'infinity'::timestamptz)
                    -- Invitation and approval claims skip the public registration window
                    else 'infinity'::timestamptz
                end,
                coalesce(v_event_starts_at, 'infinity'::timestamptz)
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
                when raise_exception then
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
            when raise_exception then
                return jsonb_build_object('conflict', 'payment-setup-unavailable');
        end;
    -- Remove payment configuration from intrinsically free purchases
    else
        v_charge_model := 'ocg-free';
        v_currency_code := null;
        v_recipient := null;
    end if;

    -- Snapshot the immutable seller and selected manual-rate components
    if v_final_amount_minor > 0 and not v_is_external_paid then
        v_seller_snapshot := jsonb_build_object(
            'connected_account_id', v_recipient->>'recipient_id',
            'display_name', v_recipient->>'seller_display_name',
            'provider', v_recipient->>'provider'
        );

        -- Reuse immutable automatic-tax resources within the seller account
        if v_tax_calculation_mode = 'automatic' then
            v_cached_performance_location_fingerprint := encode(
                digest(
                    convert_to(v_venue_snapshot->>'address', 'UTF8') || decode('00', 'hex')
                    || convert_to(v_venue_snapshot->>'city', 'UTF8') || decode('00', 'hex')
                    || convert_to(v_venue_snapshot->>'country_code', 'UTF8') || decode('00', 'hex')
                    || convert_to(v_venue_snapshot->>'name', 'UTF8') || decode('00', 'hex')
                    || convert_to(coalesce(v_venue_snapshot->>'state_code', ''), 'UTF8')
                        || decode('00', 'hex')
                    || convert_to(v_venue_snapshot->>'zip_code', 'UTF8') || decode('00', 'hex'),
                    'sha256'
                ),
                'hex'
            );

            select pptl.provider_tax_location_id
            into v_cached_provider_tax_location_id
            from payment_provider_tax_location pptl
            where pptl.payment_provider_id = p_configured_provider
            and pptl.connected_seller_id = v_recipient->>'recipient_id'
            and pptl.fingerprint = v_cached_performance_location_fingerprint;

            -- Reuse a cached ticket product for the resolved performance location
            if v_cached_provider_tax_location_id is not null then
                v_cached_product_fingerprint := encode(
                    digest(
                        convert_to(left(v_ticket_title, 250), 'UTF8') || decode('00', 'hex')
                        || convert_to(v_cached_provider_tax_location_id, 'UTF8') || decode('00', 'hex')
                        || convert_to('txcd_50013001', 'UTF8') || decode('00', 'hex'),
                        'sha256'
                    ),
                    'hex'
                );

                select pptp.provider_tax_product_id
                into v_cached_provider_tax_product_id
                from payment_provider_tax_product pptp
                where pptp.payment_provider_id = p_configured_provider
                and pptp.connected_seller_id = v_recipient->>'recipient_id'
                and pptp.fingerprint = v_cached_product_fingerprint;
            end if;
        end if;
    end if;

    -- Release any replaced pending selection before creating the new hold
    if v_existing_purchase_id is not null and v_existing_purchase_status = 'pending' then
        perform prepare_event_checkout_expire_previous_hold(v_existing_purchase_id);
    end if;

    -- Snapshot the pending offer claim and move its reservation into checkout
    if p_admission_offer_id is not null then
        -- Keep the 15-minute Stripe hold from outliving a shorter offer deadline
        if not v_is_external_paid then
            v_hold_expires_at := least(
                v_hold_expires_at,
                coalesce(v_admission_offer_expires_at, 'infinity'::timestamptz)
            );
        end if;

        -- Replace the issue snapshot with the claimed price on first checkout
        if v_admission_offer_status = 'pending' then
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
        v_registration_questions,
        p_registration_answers
    );

    -- Reserve the chosen discount usage for the new pending purchase
    if v_event_discount_code_id is not null then
        perform prepare_event_checkout_reserve_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Snapshot the platform fee deducted from the group's proceeds, rounding down
    v_provisional_platform_fee_amount_minor := case
        -- External purchases never collect a platform fee
        when v_is_external_paid then 0
        -- Stripe purchases apply the configured basis-point fee
        else (v_final_amount_minor * p_platform_fee_bps) / 10000
    end;

    -- Insert the new pending purchase and return the attendee-facing summary
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
            when v_charge_model = 'direct-charge' then v_manual_tax_rate_ids
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
            when v_charge_model = 'direct-charge' and v_tax_calculation_mode = 'automatic'
                then 'txcd_50013001'
        end,
        v_provisional_platform_fee_amount_minor,
        v_seller_snapshot,
        'pending',
        case
            -- Snapshot the tax display behavior for Stripe purchases
            when v_charge_model = 'direct-charge' then v_tax_behavior
        end,
        case
            -- Snapshot the tax calculation mode for Stripe purchases
            when v_charge_model = 'direct-charge' then v_tax_calculation_mode
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
                'deadline', extract(epoch from v_hold_expires_at)::bigint,
                'event_id', p_event_id,
                'event_name', v_event_name,
                'event_purchase_id', v_purchase_id,
                'external_payment_instructions', v_event_external_payment_instructions,
                'external_payment_url', v_event_external_payment_url,
                'group_name', v_group_name,
                'theme', v_theme,
                'ticket_title', v_ticket_title,
                'timezone', v_event_timezone
            )),
            '[]'::jsonb,
            array[p_user_id]
        );
    end if;

    -- Return the pending purchase summary used by the checkout flow
    return prepare_event_checkout_get_purchase_summary(v_purchase_id)
        || jsonb_build_object(
            'community_display_name', v_community_display_name,
            'community_name', v_community_name,
            'event_id', p_event_id,
            'event_name', v_event_name,
            'event_slug', v_event_slug,
            'event_starts_at', extract(epoch from v_event_starts_at)::bigint,
            'event_timezone', v_event_timezone,
            'group_name', v_group_name,
            'group_slug', v_group_slug,
            'group_slug_pretty', v_group_slug_pretty
        )
        || jsonb_strip_nulls(jsonb_build_object(
            'cached_performance_location_fingerprint',
                v_cached_performance_location_fingerprint,
            'cached_product_fingerprint', v_cached_product_fingerprint,
            'cached_provider_tax_location_id', v_cached_provider_tax_location_id,
            'cached_provider_tax_product_id', v_cached_provider_tax_product_id
        ));
end;
$$ language plpgsql;
