-- Declines an admission offer owned by the current user.
create or replace function decline_event_admission_offer(
    p_actor_user_id uuid,
    p_admission_offer_id uuid,
    p_configured_provider text default null
)
returns json as $$
declare
    v_community_id uuid;
    v_event_discount_code_id uuid;
    v_event_id uuid;
    v_event_name text;
    v_event_ticket_type_id uuid;
    v_group_id uuid;
    v_group_name text;
    v_organizer_user_id uuid;
    v_recipient_name text;
    v_source text;
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

    if not found then
        raise exception 'admission offer is no longer available';
    end if;

    -- Lock the event and ticket inventory before user enrollment state
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

    if not found then
        raise exception 'admission offer is no longer available';
    end if;

    perform 1
    from event_ticket_type ett
    where ett.event_id = v_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Expire stale reservations before selecting the requested offer
    perform reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_configured_provider
    );

    perform pg_advisory_xact_lock(
        hashtext(v_event_id::text),
        hashtext(p_actor_user_id::text)
    );

    -- Lock and validate the active user-owned offer
    select
        ao.organizer_user_id,
        ao.source
    into
        v_organizer_user_id,
        v_source
    from admission_offer ao
    where ao.admission_offer_id = p_admission_offer_id
    and ao.event_id = v_event_id
    and ao.status in ('checkout_pending', 'pending')
    and ao.expires_at > current_timestamp
    and ao.user_id = p_actor_user_id
    for update of ao;

    if not found then
        raise exception 'admission offer is no longer available';
    end if;

    -- Expire any linked checkout and release its discount and attendee hold
    select ep.event_discount_code_id
    into v_event_discount_code_id
    from event_purchase ep
    where ep.admission_offer_id = p_admission_offer_id
    and ep.status = 'pending'
    for update of ep;

    if found then
        update event_purchase
        set
            hold_expires_at = current_timestamp,
            status = 'expired',
            updated_at = current_timestamp
        where admission_offer_id = p_admission_offer_id
        and status = 'pending';

        if v_event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_event_discount_code_id);
        end if;

        perform release_event_checkout_attendee_hold(v_event_id, p_actor_user_id);
    end if;

    -- Persist the recipient decision and fill the released tier seat
    update admission_offer
    set
        status = 'declined',
        updated_at = current_timestamp
    where admission_offer_id = p_admission_offer_id
    and status in ('checkout_pending', 'pending');

    if not found then
        raise exception 'admission offer is no longer available';
    end if;

    perform reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_configured_provider
    );

    -- Load immutable notification context after the release succeeds
    select
        e.name,
        g.name,
        coalesce(u.name, u.username, u.email),
        s.theme,
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
    left join lateral (
        select site.theme
        from site
        order by site.created_at desc
        limit 1
    ) s on true
    where e.event_id = v_event_id;

    -- Notify the assigning organizer when one owns the released offer
    if v_organizer_user_id is not null then
        perform enqueue_notification(
            'event-admission-offer-declined',
            jsonb_build_object(
                'admission_offer_id', p_admission_offer_id,
                'dashboard_url', '/dashboard/group/events/' || v_event_id || '/attendees',
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
            array[v_organizer_user_id]
        );
    end if;

    -- Track the recipient decision after queue reconciliation succeeds
    perform insert_audit_log(
        case
            when v_source = 'organizer_invitation'
                then 'event_attendee_invitation_rejected'
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
