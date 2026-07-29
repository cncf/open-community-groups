-- Validates a ticket selection and resolves its checkout price.
create or replace function prepare_event_checkout_validate_and_resolve_pricing(
    p_event_id uuid,
    p_event_ticket_type_id uuid,
    p_user_id uuid,
    p_discount_code text,
    p_admission_offer_id uuid default null
)
returns table (
    discount_amount_minor bigint,
    event_discount_code_id uuid,
    final_amount_minor bigint,
    ticket_title text
) as $$
declare
    v_allocated_seat_count int;
    v_amount_minor bigint;
    v_discount_active boolean;
    v_discount_available int;
    v_discount_available_override_active boolean;
    v_discount_ends_at timestamptz;
    v_event_discount_code_id uuid;
    v_discount_kind text;
    v_discount_percentage int;
    v_discount_starts_at timestamptz;
    v_discount_total_available int;
    v_price_window_amount_minor bigint;
    v_redemptions int;
    v_seats_total int;
    v_ticket_active boolean;
    v_ticket_availability text;
begin
    discount_amount_minor := 0;

    -- Reject attendee states that checkout completion cannot confirm
    perform prepare_event_checkout_validate_attendee_state(p_event_id, p_user_id);

    -- Restrict offer pricing bypasses to the exact active owned reservation
    if p_admission_offer_id is not null
       and not exists (
            select 1
            from admission_offer ao
            where ao.admission_offer_id = p_admission_offer_id
            and ao.event_id = p_event_id
            and ao.event_ticket_type_id = p_event_ticket_type_id
            and ao.status in ('checkout_pending', 'pending')
            and ao.user_id = p_user_id
            and ao.expires_at > current_timestamp
       ) then
        raise exception 'admission offer is no longer available';
    end if;

    -- Resolve the selected ticket type and the currently active price window
    select
        ett.active,
        ett.availability,
        cp.amount_minor,
        ett.seats_total,
        ett.title
    into
        v_ticket_active,
        v_ticket_availability,
        v_price_window_amount_minor,
        v_seats_total,
        ticket_title
    from event_ticket_type ett
    left join lateral (
        select etpw.amount_minor
        from event_ticket_price_window etpw
        where etpw.event_ticket_type_id = ett.event_ticket_type_id
        and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
        and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
        order by
            etpw.starts_at desc nulls last,
            etpw.event_ticket_price_window_id asc
        limit 1
    ) cp on true
    where ett.event_id = p_event_id
    and ett.event_ticket_type_id = p_event_ticket_type_id;

    -- Reject missing, inactive, or unsellable ticket selections
    if not found then
        raise exception 'ticket type not found';
    end if;

    if not v_ticket_active then
        raise exception 'ticket type is not active';
    end if;

    if p_admission_offer_id is null and v_ticket_availability <> 'public' then
        raise exception 'ticket type is not available for direct checkout';
    end if;

    if v_price_window_amount_minor is null then
        raise exception 'ticket type does not have an active price window';
    end if;

    -- Preserve FIFO priority when reconciliation leaves a blocked queue head
    if p_admission_offer_id is null
       and exists (
            select 1
            from event_waitlist ew
            where ew.event_id = p_event_id
            and ew.event_ticket_type_id = p_event_ticket_type_id
       ) then
        raise exception 'ticket type has queued users';
    end if;

    -- Count allocated inventory before deciding whether the ticket is sold out
    select get_event_ticket_type_allocated_seat_count(
        p_event_id,
        p_event_ticket_type_id
    )
    into v_allocated_seat_count;

    -- Reject sold-out ticket types after counting allocated inventory
    if p_admission_offer_id is null
       and v_seats_total is not null
       and v_allocated_seat_count >= v_seats_total then
        raise exception 'ticket type is sold out';
    end if;

    -- Validate the selected discount code before creating a new hold
    if p_discount_code is not null then
        if v_price_window_amount_minor = 0 then
            raise exception 'discount codes cannot be applied to free tickets';
        end if;

        select
            edc.active,
            edc.available,
            edc.available_override_active,
            edc.ends_at,
            edc.event_discount_code_id,
            edc.kind,
            edc.percentage,
            edc.starts_at,
            edc.total_available,
            edc.amount_minor
        into
            v_discount_active,
            v_discount_available,
            v_discount_available_override_active,
            v_discount_ends_at,
            v_event_discount_code_id,
            v_discount_kind,
            v_discount_percentage,
            v_discount_starts_at,
            v_discount_total_available,
            v_amount_minor
        from event_discount_code edc
        where edc.event_id = p_event_id
        and upper(edc.code) = p_discount_code;

        -- Reject missing or unavailable discount codes before pricing
        if not found then
            raise exception 'discount code not found';
        end if;

        if not v_discount_active
           or (v_discount_starts_at is not null and current_timestamp < v_discount_starts_at)
           or (v_discount_ends_at is not null and current_timestamp > v_discount_ends_at)
           or (
                v_discount_available_override_active
                and v_discount_available is not null
                and v_discount_available <= 0
           ) then
            raise exception 'discount code is not available';
        end if;

        if v_discount_total_available is not null then
            -- Count active redemptions before applying the limited discount
            select count(*)::int
            into v_redemptions
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.event_discount_code_id = v_event_discount_code_id
            and (
                ep.status in ('completed', 'refund-requested')
                or (ep.status = 'pending' and ep.hold_expires_at > current_timestamp)
            );

            if v_redemptions >= v_discount_total_available then
                raise exception 'discount code is no longer available';
            end if;
        end if;

        -- Compute the discount amount using the configured discount strategy
        if v_discount_kind = 'fixed_amount' then
            discount_amount_minor := least(v_amount_minor, v_price_window_amount_minor);
        elsif v_discount_kind = 'percentage' then
            discount_amount_minor := v_price_window_amount_minor * v_discount_percentage / 100;
        else
            raise exception 'unsupported discount code kind';
        end if;

        -- Reject discounts that cannot reduce the price by one minor unit
        if discount_amount_minor = 0 then
            raise exception 'discount code does not reduce ticket price';
        end if;
    end if;

    -- Compute the final amount charged for the selected checkout purchase
    event_discount_code_id := v_event_discount_code_id;
    final_amount_minor := greatest(v_price_window_amount_minor - discount_amount_minor, 0);

    return next;
end;
$$ language plpgsql;
