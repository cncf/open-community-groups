-- Entry point for start_checkout: reuse an active purchase or create a pending hold
create or replace function prepare_event_checkout_purchase(
    p_community_id uuid,
    p_event_id uuid,
    p_event_ticket_type_id uuid,
    p_user_id uuid,
    p_discount_code text
)
returns jsonb as $$
declare
    v_currency_code text;
    v_discount_amount_minor bigint;
    v_event_discount_code_id uuid;
    v_existing_purchase_id uuid;
    v_existing_purchase_matches_selection boolean;
    v_existing_purchase_status text;
    v_final_amount_minor bigint;
    v_hold_expires_at timestamptz := current_timestamp + interval '15 minutes';
    v_normalized_discount_code text := upper(nullif(btrim(p_discount_code), ''));
    v_purchase_id uuid;
    v_ticket_title text;
begin
    -- Expire stale pending purchases for the event before reserving a new one
    perform prepare_event_checkout_expire_stale_holds(p_event_id);

    -- Lock the event and validate that checkout is still allowed
    v_currency_code := prepare_event_checkout_validate_event(p_community_id, p_event_id);

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
        v_normalized_discount_code
    );

    if found then
        if v_existing_purchase_status <> 'pending'
           or v_existing_purchase_matches_selection then
            return prepare_event_checkout_get_purchase_summary(v_existing_purchase_id);
        end if;
    end if;

    -- Resolve the requested ticket, discount, and final amount
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
        v_normalized_discount_code
    );

    -- Release any replaced pending selection before creating the new hold
    if v_existing_purchase_id is not null and v_existing_purchase_status = 'pending' then
        perform prepare_event_checkout_expire_previous_hold(v_existing_purchase_id);
    end if;

    -- Reserve the chosen discount usage for the new pending purchase
    if v_event_discount_code_id is not null then
        perform prepare_event_checkout_reserve_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Insert the new pending purchase and return the attendee-facing summary
    insert into event_purchase (
        amount_minor,
        currency_code,
        discount_amount_minor,
        discount_code,
        event_discount_code_id,
        event_id,
        event_ticket_type_id,
        hold_expires_at,
        status,
        ticket_title,
        user_id
    ) values (
        v_final_amount_minor,
        v_currency_code,
        v_discount_amount_minor,
        v_normalized_discount_code,
        v_event_discount_code_id,
        p_event_id,
        p_event_ticket_type_id,
        v_hold_expires_at,
        'pending',
        v_ticket_title,
        p_user_id
    )
    returning event_purchase_id into v_purchase_id;

    -- Return the pending purchase summary used by the checkout flow
    return prepare_event_checkout_get_purchase_summary(v_purchase_id);
end;
$$ language plpgsql;
