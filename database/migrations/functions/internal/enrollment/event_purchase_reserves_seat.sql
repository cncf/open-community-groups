-- Returns whether an event purchase currently reserves a seat: its status holds
-- the seat, or it is a pending checkout whose hold has not expired.
create or replace function event_purchase_reserves_seat(
    p_status text,
    p_hold_expires_at timestamptz
)
returns boolean as $$
    select event_purchase_holds_seat(p_status)
        or (p_status = 'pending' and p_hold_expires_at > current_timestamp);
$$ language sql stable;
