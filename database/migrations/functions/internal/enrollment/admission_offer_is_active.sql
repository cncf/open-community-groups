-- Returns whether an admission offer status still reserves a seat for its
-- user: offers waiting to be accepted and offers with a checkout in progress.
create or replace function admission_offer_is_active(p_status text)
returns boolean as $$
    select p_status in ('checkout_pending', 'pending');
$$ language sql immutable;
