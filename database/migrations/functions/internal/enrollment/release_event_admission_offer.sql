-- Releases a user's active admission offer as canceled or declined under the
-- enrollment lock order: reconciles the event, serializes the user, locks the
-- live offer, expires its linked checkout hold, stores the decision and
-- refills the released tier seat. Callers lock the event row first and own
-- scope checks, notifications and audit. Returns the updated offer.
create or replace function release_event_admission_offer(
    p_event_id uuid,
    p_event_ticket_type_id uuid,
    p_user_id uuid,
    p_admission_offer_id uuid,
    p_status text,
    p_configured_provider text
)
returns admission_offer as $$
declare
    v_event_purchase_id uuid;
    v_offer admission_offer;
begin
    -- Reject release decisions other than cancel and decline
    if p_status is null or p_status not in ('canceled', 'declined') then
        raise exception 'invalid admission offer release status: %', p_status;
    end if;

    -- Expire stale reservations under the global lock order, serializing the user
    perform reconcile_event_enrollment(
        p_event_id,
        p_event_ticket_type_id,
        p_configured_provider,
        p_user_id
    );

    -- Lock the user's live offer in the event
    select ao.*
    into v_offer
    from admission_offer ao
    where ao.admission_offer_id = p_admission_offer_id
    and ao.event_id = p_event_id
    and ao.user_id = p_user_id
    and admission_offer_reserves_seat(ao.status, ao.expires_at)
    for update of ao;

    -- Reject offers that are no longer active or have expired
    if not found then
        raise exception 'admission offer is no longer available' using errcode = 'OCG01';
    end if;

    -- Lock the pending checkout linked to the offer
    select ep.event_purchase_id
    into v_event_purchase_id
    from event_purchase ep
    where ep.admission_offer_id = p_admission_offer_id
    and ep.status = 'pending'
    for update of ep;

    -- Expire the linked checkout and release its discount and attendee hold
    if found then
        perform expire_event_checkout_hold(v_event_purchase_id);
    end if;

    -- Persist the release decision
    update admission_offer
    set
        status = p_status,
        updated_at = current_timestamp
    where admission_offer_id = p_admission_offer_id
    and admission_offer_is_active(status)
    returning * into v_offer;

    -- Reject offers that are no longer active
    if not found then
        raise exception 'admission offer is no longer available' using errcode = 'OCG01';
    end if;

    -- Offer the released seat to the next eligible candidate
    perform reconcile_event_enrollment(
        p_event_id,
        p_event_ticket_type_id,
        p_configured_provider
    );

    -- Return the released offer
    return v_offer;
end;
$$ language plpgsql;
