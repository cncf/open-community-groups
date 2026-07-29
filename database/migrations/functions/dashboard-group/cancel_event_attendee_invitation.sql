-- Cancels a pending organizer-created RSVP invitation.
create or replace function cancel_event_attendee_invitation(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_configured_provider text default null
)
returns void as $$
declare
    v_admission_offer_id uuid;
begin
    -- Resolve the group-scoped RSVP invitation before using the generic release flow
    select ao.admission_offer_id
    into v_admission_offer_id
    from admission_offer ao
    join event e using (event_id)
    where ao.event_id = p_event_id
    and ao.event_ticket_type_id is null
    and ao.source = 'organizer_invitation'
    and ao.status in ('checkout_pending', 'pending')
    and ao.user_id = p_user_id
    and e.group_id = p_group_id;

    if not found then
        if not exists (
            select 1
            from event e
            where e.event_id = p_event_id
            and e.group_id = p_group_id
            and e.deleted = false
        ) then
            raise exception 'event not found';
        end if;

        raise exception 'pending event invitation not found';
    end if;

    -- Cancel the exact invitation and reconcile released capacity
    begin
        perform cancel_event_admission_offer(
            p_actor_user_id,
            p_group_id,
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
