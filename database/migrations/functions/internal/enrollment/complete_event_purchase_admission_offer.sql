-- Completes the checkout-pending admission offer linked to a purchase that is
-- being completed. Returns false when the offer already left the
-- checkout-pending state so callers can reject the completion.
create or replace function complete_event_purchase_admission_offer(p_admission_offer_id uuid)
returns boolean as $$
begin
    -- Move the reservation into its terminal completed state
    update admission_offer
    set
        status = 'completed',
        updated_at = current_timestamp
    where admission_offer_id = p_admission_offer_id
    and status = 'checkout_pending';

    return found;
end;
$$ language plpgsql;
