-- Returns the redemption count of a discount code enforced against its
-- total_available limit: settled sales and live checkout holds. Discounts of
-- refunding purchases are already released through the inventory lifecycle.
create or replace function event_discount_code_redemption_count(p_event_discount_code_id uuid)
returns int as $$
    select count(*)::int
    from event_purchase ep
    where ep.event_discount_code_id = p_event_discount_code_id
    and (
        ep.status in ('completed', 'refund-requested')
        or (ep.status = 'pending' and ep.hold_expires_at > current_timestamp)
    );
$$ language sql stable;
