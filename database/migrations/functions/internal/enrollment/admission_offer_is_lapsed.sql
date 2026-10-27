-- Returns whether an admission offer is still active by status but its deadline
-- has passed, so reconciliation must expire it.
create or replace function admission_offer_is_lapsed(
    p_status text,
    p_expires_at timestamptz
)
returns boolean as $$
    select admission_offer_is_active(p_status)
        and p_expires_at <= current_timestamp;
$$ language sql stable;
