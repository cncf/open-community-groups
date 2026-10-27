-- Returns whether an admission offer status is active: offers waiting to be
-- accepted and offers with a checkout in progress. It checks the status only;
-- admission_offer_reserves_seat also checks the deadline.
create or replace function admission_offer_is_active(p_status text)
returns boolean as $$
    select p_status in ('checkout_pending', 'pending');
$$ language sql immutable;
