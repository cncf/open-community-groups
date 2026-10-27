-- Returns the purchase holding each attendee's seat for an event: the latest
-- completed seat-holding purchase per user, falling back to the newest one.
-- Several can coexist because a purchase whose refund is in flight keeps its
-- seat next to a replacement or a late-paid hold that never completed.
create or replace function event_seat_purchases(p_event_id uuid)
returns table (
    admission_offer_id uuid,
    event_purchase_id uuid,
    event_ticket_type_id uuid,
    ticket_title text,
    user_id uuid
) as $$
    select distinct on (ep.user_id)
        ep.admission_offer_id,
        ep.event_purchase_id,
        ep.event_ticket_type_id,
        ep.ticket_title,
        ep.user_id
    from event_purchase ep
    where ep.event_id = p_event_id
    and event_purchase_holds_seat(ep.status)
    order by
        ep.user_id,
        ep.completed_at desc nulls last,
        ep.created_at desc,
        ep.event_purchase_id desc;
$$ language sql stable;
