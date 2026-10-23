-- Completes a pending free-ticket purchase and returns its notification data.
create or replace function complete_free_event_purchase(
    p_event_purchase_id uuid
)
returns jsonb as $$
declare
    v_admission_offer admission_offer;
    v_event event;
    v_group "group";
    v_lock record;
    v_purchase event_purchase;
begin
    -- Lock the group, event and purchase, reconciling enrollment before the purchase lock
    select *
    into v_lock
    from lock_event_purchase_for_completion(p_event_purchase_id, null);
    v_admission_offer := v_lock.admission_offer_row;
    v_event := v_lock.event_row;
    v_group := v_lock.group_row;
    v_purchase := v_lock.purchase_row;

    -- Reject purchases that left the pending state
    if v_purchase.status <> 'pending' then
        raise exception 'purchase is no longer pending' using errcode = 'OCG01';
    end if;

    -- Reject paid purchases, which only the provider webhook completes
    if v_purchase.amount_minor <> 0 then
        raise exception 'only free purchases can be completed locally' using errcode = 'OCG01';
    end if;

    -- Complete the reservation and confirm the attendee seat
    perform fulfill_event_purchase_seat(v_purchase, v_event, v_group, v_admission_offer);

    -- Persist the completed free purchase
    update event_purchase
    set
        completed_at = current_timestamp,
        hold_expires_at = null,
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Return the identifiers needed by the caller after completion
    return jsonb_build_object(
        'community_id', v_group.community_id,
        'event_id', v_event.event_id,
        'user_id', v_purchase.user_id
    );
end;
$$ language plpgsql;
