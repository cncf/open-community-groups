-- Finds an attendee's active purchase for a ticket selection. Purchases in
-- refund recovery are found regardless of their admission offer, so checkout
-- on either path stays blocked until the recovery settles.
create or replace function prepare_event_checkout_find_existing_purchase(
    p_event_id uuid,
    p_event_ticket_type_id uuid,
    p_user_id uuid,
    p_discount_code text,
    p_admission_offer_id uuid default null
)
returns table (
    event_purchase_id uuid,
    matches_selection boolean,
    status text
) as $$
    select
        ep.event_purchase_id,
        ep.event_ticket_type_id = p_event_ticket_type_id
            and upper(nullif(btrim(ep.discount_code), '')) is not distinct from p_discount_code,
        ep.status
    from event_purchase ep
    where ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and (
        ep.admission_offer_id is not distinct from p_admission_offer_id
        or ep.status = 'refund-recovery-pending'
    )
    -- Block checkout during recovery without invalidating a completed replacement purchase
    and event_purchase_reserves_seat(ep.status, ep.hold_expires_at)
    order by
        case
            when ep.status = 'completed' then 0
            when ep.status in (
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            ) then 1
            else 2
        end,
        ep.created_at desc,
        ep.event_purchase_id desc
    limit 1;
$$ language sql stable;
