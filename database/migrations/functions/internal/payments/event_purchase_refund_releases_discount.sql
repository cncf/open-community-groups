-- Returns whether finalizing a refund of this kind returns its discount
-- reservation. Unfulfillable-checkout refunds released it when the hold expired
-- or moved to refund-pending.
create or replace function event_purchase_refund_releases_discount(p_kind text)
returns boolean as $$
    select p_kind <> 'automatic-unfulfillable-checkout';
$$ language sql immutable;
