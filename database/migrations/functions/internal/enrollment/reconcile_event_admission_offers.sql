-- Expires the due admission offers of an event, auditing each expiry, and
-- returns checkout-pending offers whose checkout was abandoned to pending so
-- the holder can claim them again. Callers hold the event enrollment locks.
create or replace function reconcile_event_admission_offers(
    p_event event,
    p_group "group"
)
returns void as $$
declare
    v_admission_offer admission_offer;
begin
    -- Expire due offers or return abandoned checkout offers to pending
    for v_admission_offer in
        select ao.*
        from admission_offer ao
        where ao.event_id = p_event.event_id
        and admission_offer_is_active(ao.status)
        order by ao.admission_offer_id
    loop
        -- Expire offers past their deadline
        if v_admission_offer.expires_at is not null
           and v_admission_offer.expires_at <= current_timestamp then
            update admission_offer
            set
                status = 'expired',
                updated_at = current_timestamp
            where admission_offer_id = v_admission_offer.admission_offer_id
            and status = v_admission_offer.status;

            -- Track the expiry once the transition is confirmed
            if found then
                perform insert_audit_log(
                    'admission_offer_expired',
                    null,
                    'admission_offer',
                    v_admission_offer.admission_offer_id,
                    p_group.community_id,
                    p_event.group_id,
                    p_event.event_id,
                    jsonb_build_object(
                        'admission_offer_id', v_admission_offer.admission_offer_id,
                        'user_id', v_admission_offer.user_id
                    )
                );
            end if;

        -- Return offers whose checkout no longer holds or reserves a seat to pending
        elsif v_admission_offer.status = 'checkout_pending'
              and not exists (
                    select 1
                    from event_purchase ep
                    where ep.admission_offer_id = v_admission_offer.admission_offer_id
                    and (
                        event_purchase_holds_seat(ep.status)
                        or (
                            ep.status = 'pending'
                            and ep.hold_expires_at > current_timestamp
                        )
                    )
              ) then
            update admission_offer
            set
                status = 'pending',
                updated_at = current_timestamp
            where admission_offer_id = v_admission_offer.admission_offer_id
            and status = 'checkout_pending';
        end if;
    end loop;
end;
$$ language plpgsql;
