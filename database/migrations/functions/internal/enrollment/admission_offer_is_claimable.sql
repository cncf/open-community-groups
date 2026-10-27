-- Returns whether its user can still claim an admission offer: the offer
-- reserves a seat and no purchase linked to it is being refunded.
create or replace function admission_offer_is_claimable(p_offer admission_offer)
returns boolean as $$
    select admission_offer_reserves_seat(p_offer.status, p_offer.expires_at)
        and not exists (
            select 1
            from event_purchase ep
            where ep.admission_offer_id = p_offer.admission_offer_id
            and ep.status in (
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
        );
$$ language sql stable;
