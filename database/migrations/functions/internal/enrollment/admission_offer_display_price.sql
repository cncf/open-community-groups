-- Returns the price shown for an admission offer. Pending offers without a
-- discount follow the live ticket price and fall back to the snapshot only for
-- approval and organizer offers; other offers keep their snapshot. The currency
-- is shown only for paid or discounted offers, defaulting to the event currency.
create or replace function admission_offer_display_price(
    p_admission_offer admission_offer,
    p_event event
)
returns table (
    amount_minor bigint,
    currency_code text
) as $$
    select
        dp.amount_minor,
        case
            when dp.amount_minor > 0
                 or (
                    (
                        p_admission_offer.status <> 'pending'
                        or p_admission_offer.discount_code is not null
                    )
                    and coalesce(p_admission_offer.discount_amount_minor, 0) > 0
                 )
                then coalesce(dp.currency_code, p_event.payment_currency_code)
        end as currency_code
    -- Resolve the live price of the offer ticket tier
    from (
        select event_ticket_type_current_price(p_admission_offer.event_ticket_type_id) as amount_minor
    ) cp
    -- Pick the live price or the offer snapshot
    cross join lateral (
        select
            case
                when p_admission_offer.status = 'pending'
                     and p_admission_offer.discount_code is null
                    then coalesce(
                        cp.amount_minor,
                        case
                            when p_admission_offer.source in ('approval', 'organizer_invitation')
                                then p_admission_offer.amount_minor
                        end
                    )
                else coalesce(p_admission_offer.amount_minor, cp.amount_minor)
            end as amount_minor,
            case
                when p_admission_offer.status = 'pending'
                     and p_admission_offer.discount_code is null
                     and cp.amount_minor is not null
                    then p_event.payment_currency_code
                else p_admission_offer.currency_code
            end as currency_code
    ) dp;
$$ language sql stable;
