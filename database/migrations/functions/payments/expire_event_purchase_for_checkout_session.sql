-- Expires a pending purchase and releases its checkout reservations.
create or replace function expire_event_purchase_for_checkout_session(
    p_provider text,
    p_provider_session_id text
)
returns void as $$
declare
    v_event_discount_code_id uuid;
    v_event_id uuid;
    v_event_ticket_type_id uuid;
    v_user_id uuid;
begin
    -- Resolve the owning event before taking lifecycle locks
    select
        ep.event_id,
        ep.event_ticket_type_id
    into
        v_event_id,
        v_event_ticket_type_id
    from event_purchase ep
    where ep.payment_provider_id = p_provider
    and ep.provider_checkout_session_id = p_provider_session_id;

    if not found then
        return;
    end if;

    -- Reconcile under the global event, tier, user, and purchase lock order
    perform reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_provider
    );

    -- Expire the pending purchase linked to the provider checkout session
    update event_purchase
    set
        hold_expires_at = least(hold_expires_at, current_timestamp),
        status = 'expired',
        updated_at = current_timestamp
    where payment_provider_id = p_provider
    and provider_checkout_session_id = p_provider_session_id
    and status = 'pending'
    returning
        event_discount_code_id,
        event_id,
        user_id
    into
        v_event_discount_code_id,
        v_event_id,
        v_user_id;

    -- Restore any reserved discount usage released by the expired purchase
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Release the pending attendee row created for checkout answers
    if v_event_id is not null then
        perform release_event_checkout_attendee_hold(v_event_id, v_user_id);

        -- Return linked offers to pending and fill the released capacity
        perform reconcile_event_enrollment(
            v_event_id,
            v_event_ticket_type_id,
            p_provider
        );
    end if;
end;
$$ language plpgsql;
