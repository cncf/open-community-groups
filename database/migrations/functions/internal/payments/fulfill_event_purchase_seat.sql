-- Validates that a locked pending purchase can still take its seat, then
-- completes its linked admission offer and confirms the attendee row.
create or replace function fulfill_event_purchase_seat(
    p_purchase event_purchase,
    p_event event,
    p_group "group",
    p_admission_offer admission_offer
)
returns void as $$
begin
    -- Reject holds that expired during reconciliation
    if p_purchase.hold_expires_at is not null and p_purchase.hold_expires_at <= current_timestamp then
        raise exception 'purchase hold has expired' using errcode = 'OCG01';
    end if;

    -- Reject completion while another purchase is in refund recovery
    if event_has_pending_refund_recovery(p_purchase.event_id, p_purchase.user_id, p_purchase.event_purchase_id) then
        raise exception 'checkout is unavailable while refund recovery is in progress' using errcode = 'OCG01';
    end if;

    -- Ensure the event is still active before completing the purchase
    if not event_accepts_enrollment(p_event, p_group) then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Complete the linked reservation before creating active attendance
    if p_purchase.admission_offer_id is not null
       and not complete_event_purchase_admission_offer(p_purchase.admission_offer_id) then
        raise exception 'admission offer is no longer available' using errcode = 'OCG01';
    end if;

    -- Never complete the purchase without a confirmed attendee row
    if not confirm_event_purchase_attendee(
        p_purchase.event_id,
        p_purchase.user_id,
        coalesce(p_admission_offer.source = 'organizer_invitation', false)
    ) then
        raise exception 'attendee cannot be confirmed for this event' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;
