-- Used by prepare_event_checkout_purchase to validate selection and price checkout
create or replace function prepare_event_checkout_validate_and_resolve_pricing(
    p_event_id uuid,
    p_event_ticket_type_id uuid,
    p_user_id uuid,
    p_discount_code text
)
returns table (
    discount_amount_minor bigint,
    event_discount_code_id uuid,
    final_amount_minor bigint,
    ticket_title text
) as $$
declare
    v_active_purchase_count int;
    v_amount_minor bigint;
    v_discount_active boolean;
    v_discount_available int;
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
begin
    discount_amount_minor := 0;

    -- Prevent duplicate attendance before creating a pending purchase
    if exists (
        select 1
        from event_attendee
        where event_id = p_event_id
        and user_id = p_user_id
    ) then
        raise exception 'user is already attending this ticketed event';
    end if;

    -- Resolve the selected ticket type and the currently active price window
    select
        ett.active,
        cp.amount_minor,
        ett.seats_total,
        ett.title
    into
        v_ticket_active,
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

    if v_price_window_amount_minor is null then
        raise exception 'ticket type does not have an active price window';
    end if;

    -- Count active reservations before deciding whether the ticket is sold out
    select count(*)::int
    into v_active_purchase_count
    from event_purchase
    where event_id = p_event_id
    and event_ticket_type_id = p_event_ticket_type_id
    and (
        status in ('completed', 'refund-requested')
        or (status = 'pending' and hold_expires_at > current_timestamp)
    );

    -- Reject sold-out ticket types after counting active reservations
    if v_seats_total is not null and v_active_purchase_count >= v_seats_total then
        raise exception 'ticket type is sold out';
    end if;

    -- Validate the selected discount code before creating a new hold
    if p_discount_code is not null then
        select
            edc.active,
            edc.available,
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
           or (v_discount_available is not null and v_discount_available <= 0) then
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
    end if;

    -- Compute the final amount charged for the selected checkout purchase
    event_discount_code_id := v_event_discount_code_id;
    final_amount_minor := greatest(v_price_window_amount_minor - discount_amount_minor, 0);

    return next;
end;
$$ language plpgsql;
