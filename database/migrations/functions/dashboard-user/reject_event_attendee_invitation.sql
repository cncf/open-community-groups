-- Rejects a pending organizer-created RSVP invitation.
create or replace function reject_event_attendee_invitation(
    p_actor_user_id uuid,
    p_event_id uuid,
    p_configured_provider text default null
)
returns void as $$
declare
    v_admission_offer_id uuid;
begin
    -- Resolve the owned RSVP invitation before using the generic release flow
    select ao.admission_offer_id
    into v_admission_offer_id
    from admission_offer ao
    where ao.event_id = p_event_id
    and ao.event_ticket_type_id is null
    and ao.source = 'organizer_invitation'
    and ao.status in ('checkout_pending', 'pending')
    and ao.user_id = p_actor_user_id;

    if not found then
        raise exception 'pending event invitation not found';
    end if;

    -- Decline the exact invitation and reconcile released capacity
    begin
        perform decline_event_admission_offer(
            p_actor_user_id,
            v_admission_offer_id,
            p_configured_provider
        );
    exception
        when raise_exception then
            if sqlerrm = 'admission offer is no longer available' then
                raise exception 'pending event invitation not found';
            end if;

            raise;
    end;
end;
$$ language plpgsql;
