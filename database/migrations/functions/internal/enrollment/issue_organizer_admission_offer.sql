-- Issues a pending organizer admission offer (approval or invitation) that
-- snapshots the tier's issue price and title, keeps free offers currency-free
-- and bounds the claim deadline to the remaining event window. Callers hold the
-- enrollment locks and have validated capacity and payment readiness.
create or replace function issue_organizer_admission_offer(
    p_actor_user_id uuid,
    p_event event,
    p_ticket_type event_ticket_type,
    p_user_id uuid,
    p_amount_minor bigint,
    p_source text
)
returns admission_offer as $$
declare
    v_offer admission_offer;
begin
    -- Reject sources that are not issued by organizers
    if p_source is null or p_source not in ('approval', 'organizer_invitation') then
        raise exception 'invalid organizer admission offer source: %', p_source;
    end if;

    -- Reserve the seat with a pending offer, its issue price and a bounded deadline
    insert into admission_offer (
        amount_minor,
        currency_code,
        discount_amount_minor,
        event_id,
        event_ticket_type_id,
        expires_at,
        organizer_user_id,
        source,
        status,
        ticket_title,
        user_id
    ) values (
        p_amount_minor,
        case
            -- Snapshot the event currency for paid offers
            when p_amount_minor > 0 then p_event.payment_currency_code
            -- Keep free offers currency-free
            else null
        end,
        0,
        p_event.event_id,
        p_ticket_type.event_ticket_type_id,
        resolve_organizer_offer_expiry(p_event),
        p_actor_user_id,
        p_source,
        'pending',
        p_ticket_type.title,
        p_user_id
    )
    returning * into v_offer;

    -- Return the issued offer
    return v_offer;
end;
$$ language plpgsql;
