-- Cancels an active admission offer in an organizer's group.
create or replace function cancel_event_admission_offer(
    p_actor_user_id uuid,
    p_group_id uuid,
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
    v_group_name text;
    v_source text;
    v_theme jsonb;
    v_ticket_title text;
    v_user_id uuid;
begin
    -- Resolve immutable offer identifiers before taking lifecycle locks
    select
        ao.event_id,
        ao.event_ticket_type_id,
        ao.user_id
    into
        v_event_id,
        v_event_ticket_type_id,
        v_user_id
    from admission_offer ao
    where ao.admission_offer_id = p_admission_offer_id;

    if not found then
        raise exception 'admission offer is no longer available';
    end if;

    -- Lock the organizer-owned event and ticket inventory
    select g.community_id
    into v_community_id
    from event e
    join "group" g using (group_id)
    where e.event_id = v_event_id
    and e.group_id = p_group_id
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
        hashtext(v_user_id::text)
    );

    -- Lock and validate the active group-scoped offer
    select ao.source
    into v_source
    from admission_offer ao
    where ao.admission_offer_id = p_admission_offer_id
    and ao.event_id = v_event_id
    and ao.status in ('checkout_pending', 'pending')
    and ao.expires_at > current_timestamp
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

        perform release_event_checkout_attendee_hold(v_event_id, v_user_id);
    end if;

    -- Persist the organizer cancellation and fill the released tier seat
    update admission_offer
    set
        status = 'canceled',
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
        s.theme,
        coalesce(ao.ticket_title, ett.title)
    into
        v_event_name,
        v_group_name,
        v_theme,
        v_ticket_title
    from event e
    join "group" g using (group_id)
    join admission_offer ao on ao.admission_offer_id = p_admission_offer_id
    join event_ticket_type ett using (event_ticket_type_id)
    left join lateral (
        select site.theme
        from site
        order by site.created_at desc
        limit 1
    ) s on true
    where e.event_id = v_event_id;

    -- Notify the recipient in the same transaction as the released reservation
    perform enqueue_notification(
        'event-admission-offer-canceled',
        jsonb_build_object(
            'admission_offer_id', p_admission_offer_id,
            'dashboard_url', '/dashboard/user?tab=events',
            'event_id', v_event_id,
            'event_name', v_event_name,
            'event_ticket_type_id', v_event_ticket_type_id,
            'group_name', v_group_name,
            'theme', v_theme,
            'ticket_title', v_ticket_title,
            'user_id', v_user_id
        ),
        '[]'::jsonb,
        array[v_user_id]
    );

    -- Track the organizer decision after queue reconciliation succeeds
    perform insert_audit_log(
        case
            when v_source = 'organizer_invitation'
                then 'event_attendee_invitation_canceled'
            else 'event_admission_offer_canceled'
        end,
        p_actor_user_id,
        'user',
        v_user_id,
        v_community_id,
        p_group_id,
        v_event_id,
        jsonb_build_object(
            'admission_offer_id', p_admission_offer_id,
            'event_id', v_event_id,
            'event_ticket_type_id', v_event_ticket_type_id,
            'user_id', v_user_id
        )
    );

    -- Return the organizer refresh context
    return json_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id,
        'group_id', p_group_id
    );
end;
$$ language plpgsql;
