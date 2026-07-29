-- Accepts an exact non-ticketed organizer admission offer owned by the user.
create or replace function accept_event_admission_offer(
    p_actor_user_id uuid,
    p_admission_offer_id uuid,
    p_registration_answers jsonb default null,
    p_configured_provider text default null
)
returns jsonb as $$
declare
    v_community_id uuid;
    v_event_id uuid;
begin
    -- Resolve the owned RSVP offer without locking enrollment rows out of order
    select
        g.community_id,
        ao.event_id
    into
        v_community_id,
        v_event_id
    from admission_offer ao
    join event e using (event_id)
    join "group" g using (group_id)
    where ao.admission_offer_id = p_admission_offer_id
    and ao.event_ticket_type_id is null
    and ao.source = 'organizer_invitation'
    and ao.user_id = p_actor_user_id;

    if not found then
        return jsonb_build_object('conflict', 'admission-offer-unavailable');
    end if;

    -- Expire stale reservations and serialize the recipient before claiming
    perform reconcile_event_enrollment(
        v_event_id,
        null,
        p_configured_provider
    );
    perform pg_advisory_xact_lock(
        hashtext(v_event_id::text),
        hashtext(p_actor_user_id::text)
    );

    -- Complete only the offer identified by the current route
    if not complete_non_ticketed_event_admission_offer(
        v_community_id,
        v_event_id,
        p_actor_user_id,
        p_registration_answers,
        p_admission_offer_id
    ) then
        return jsonb_build_object('conflict', 'admission-offer-unavailable');
    end if;

    -- Return the identifiers the caller uses after acceptance
    return jsonb_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id
    );
end;
$$ language plpgsql;
