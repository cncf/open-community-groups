-- Declines an admission offer owned by the current user.
create or replace function decline_event_admission_offer(
    p_actor_user_id uuid,
    p_admission_offer_id uuid,
    p_configured_provider text default null
)
returns json as $$
declare
    v_community_id uuid;
    v_event_id uuid;
    v_event_name text;
    v_event_ticket_type_id uuid;
    v_group_id uuid;
    v_group_name text;
    v_offer admission_offer;
    v_recipient_name text;
    v_theme jsonb;
    v_ticket_title text;
begin
    -- Resolve immutable offer identifiers before taking lifecycle locks
    select
        ao.event_id,
        ao.event_ticket_type_id
    into
        v_event_id,
        v_event_ticket_type_id
    from admission_offer ao
    where ao.admission_offer_id = p_admission_offer_id
    and ao.user_id = p_actor_user_id;

    -- Reject offers that the user cannot decline
    if not found then
        raise exception 'admission offer is no longer available' using errcode = 'OCG01';
    end if;

    -- Lock the event before ticket inventory and user enrollment state
    select
        g.community_id,
        e.group_id
    into
        v_community_id,
        v_group_id
    from event e
    join "group" g using (group_id)
    where e.event_id = v_event_id
    for update of e;

    -- Reject offers whose event context disappeared
    if not found then
        raise exception 'admission offer is no longer available' using errcode = 'OCG01';
    end if;

    -- Release the active offer and fill the released tier seat
    v_offer := release_event_admission_offer(
        v_event_id,
        v_event_ticket_type_id,
        p_actor_user_id,
        p_admission_offer_id,
        'declined',
        p_configured_provider
    );

    -- Load immutable notification context after the release succeeds
    select
        e.name,
        g.name,
        coalesce(u.name, u.username, u.email),
        site_theme(),
        coalesce(ao.ticket_title, ett.title)
    into
        v_event_name,
        v_group_name,
        v_recipient_name,
        v_theme,
        v_ticket_title
    from event e
    join "group" g using (group_id)
    join admission_offer ao on ao.admission_offer_id = p_admission_offer_id
    join event_ticket_type ett using (event_ticket_type_id)
    join "user" u on u.user_id = p_actor_user_id
    where e.event_id = v_event_id;

    -- Notify the assigning organizer when one owns the released offer
    if v_offer.organizer_user_id is not null then
        perform enqueue_notification(
            'event-admission-offer-declined',
            jsonb_build_object(
                'admission_offer_id', p_admission_offer_id,
                'dashboard_url', '/dashboard/group?tab=events',
                'event_id', v_event_id,
                'event_name', v_event_name,
                'event_ticket_type_id', v_event_ticket_type_id,
                'group_name', v_group_name,
                'recipient_name', v_recipient_name,
                'theme', v_theme,
                'ticket_title', v_ticket_title,
                'user_id', p_actor_user_id
            ),
            '[]'::jsonb,
            array[v_offer.organizer_user_id]
        );
    end if;

    -- Track the recipient decision after queue reconciliation succeeds
    perform insert_audit_log(
        case
            -- Record organizer invitations as rejected invitations
            when v_offer.source = 'organizer_invitation'
                then 'event_attendee_invitation_rejected'
            -- Record every other offer as a declined admission offer
            else 'event_admission_offer_declined'
        end,
        p_actor_user_id,
        'user',
        p_actor_user_id,
        v_community_id,
        v_group_id,
        v_event_id,
        jsonb_build_object(
            'admission_offer_id', p_admission_offer_id,
            'event_id', v_event_id,
            'event_ticket_type_id', v_event_ticket_type_id,
            'user_id', p_actor_user_id
        )
    );

    -- Return the user dashboard refresh context
    return json_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id,
        'group_id', v_group_id
    );
end;
$$ language plpgsql;
