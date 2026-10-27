-- Refunds a free or external purchase locally, without provider work: marks it
-- refunded, restores its discount reservation and approves any refund request
-- still waiting for review. Callers hold the purchase's enrollment locks.
create or replace function refund_event_purchase_locally(
    p_event_purchase_id uuid,
    p_actor_user_id uuid
)
returns void as $$
declare
    v_event_discount_code_id uuid;
begin
    -- Lock the purchase and validate that it can be refunded without provider work
    select event_discount_code_id
    into v_event_discount_code_id
    from event_purchase
    where event_purchase_id = p_event_purchase_id
    and (
        amount_minor = 0
        or charge_model = 'external'
    )
    and status in ('completed', 'refund-requested')
    for update;

    -- Reject purchases outside the local refund boundary
    if not found then
        raise exception 'locally refundable purchase not found';
    end if;

    -- Persist the refunded purchase state
    update event_purchase
    set
        refunded_at = current_timestamp,
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Release the discount redemption reserved by the purchase
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Approve the refund request still waiting for review, keeping an earlier reviewer
    update event_refund_request
    set
        reviewed_at = coalesce(reviewed_at, current_timestamp),
        reviewed_by_user_id = coalesce(reviewed_by_user_id, p_actor_user_id),
        status = 'approved',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id
    and status in ('approving', 'pending');
end;
$$ language plpgsql;
