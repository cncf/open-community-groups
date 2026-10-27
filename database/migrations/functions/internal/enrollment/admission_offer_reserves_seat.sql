-- Returns whether an admission offer still reserves a seat for its user: its
-- status is active and its deadline has not passed.
create or replace function admission_offer_reserves_seat(
    p_status text,
    p_expires_at timestamptz
)
returns boolean as $$
    select admission_offer_is_active(p_status)
        and p_expires_at > current_timestamp;
$$ language sql stable;
