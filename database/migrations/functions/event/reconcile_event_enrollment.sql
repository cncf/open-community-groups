-- Expires stale enrollment reservations and promotes eligible waitlist entries.
create or replace function reconcile_event_enrollment(
    p_event_id uuid,
    p_event_ticket_type_id uuid default null,
    p_configured_provider text default null
)
returns uuid[] as $$
declare
    v_admission_offer record;
    v_allocated_seat_count int;
    v_community_id uuid;
    v_event_active boolean;
    v_event_name text;
    v_event_purchase record;
    v_event_registration_open boolean;
    v_group_id uuid;
    v_group_name text;
    v_group_payment_recipient jsonb;
    v_is_simple_rsvp boolean;
    v_offer_expires_at timestamptz;
    v_offer_id uuid;
    v_payment_currency_code text;
    v_price_amount_minor bigint;
    v_promoted_user_ids uuid[] := array[]::uuid[];
    v_registration_ends_at timestamptz;
    v_registration_starts_at timestamptz;
    v_starts_at timestamptz;
    v_theme jsonb;
    v_ticket_type record;
    v_timezone text;
    v_user_id uuid;
    v_waitlist_entry record;
begin
    -- Lock the event before every tier and enrollment row touched below
    select
        g.community_id,
        g.active = true
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and (e.starts_at is null or e.starts_at > current_timestamp),
        e.name,
        e.group_id,
        g.name,
        g.payment_recipient,
        e.payment_currency_code,
        e.registration_ends_at,
        e.registration_starts_at,
        e.starts_at,
        e.timezone
    into
        v_community_id,
        v_event_active,
        v_event_name,
        v_group_id,
        v_group_name,
        v_group_payment_recipient,
        v_payment_currency_code,
        v_registration_ends_at,
        v_registration_starts_at,
        v_starts_at,
        v_timezone
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    for update of e;

    if not found then
        return array[]::uuid[];
    end if;

    -- Resolve attendee wording from the event's public ticket shape
    v_is_simple_rsvp := is_event_simple_rsvp(p_event_id);

    -- Lock affected ticket tiers in stable identifier order
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Reject a scoped ticket type that does not belong to the locked event
    if p_event_ticket_type_id is not null
       and not exists (
            select 1
            from event_ticket_type ett
            where ett.event_id = p_event_id
            and ett.event_ticket_type_id = p_event_ticket_type_id
       ) then
        raise exception 'ticket type not found';
    end if;

    -- Acquire every affected event-user lock before enrollment row locks
    for v_user_id in
        select affected_user.user_id
        from (
            select ao.user_id
            from admission_offer ao
            where ao.event_id = p_event_id
            and ao.status in ('checkout_pending', 'pending')

            union

            select ep.user_id
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.status = 'pending'

            union

            select ew.user_id
            from event_waitlist ew
            where ew.event_id = p_event_id
            and (
                p_event_ticket_type_id is null
                or ew.event_ticket_type_id = p_event_ticket_type_id
            )
        ) affected_user
        order by affected_user.user_id
    loop
        perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(v_user_id::text));
    end loop;

    -- Lock active offers and pending purchases in stable identifier order
    perform 1
    from admission_offer ao
    where ao.event_id = p_event_id
    and ao.status in ('checkout_pending', 'pending')
    order by ao.admission_offer_id
    for update of ao;

    perform 1
    from event_purchase ep
    where ep.event_id = p_event_id
    and ep.status = 'pending'
    order by ep.event_purchase_id
    for update of ep;

    -- Expire stale checkout holds, including holds that outlive their offer
    for v_event_purchase in
        select
            ep.admission_offer_id,
            ep.event_discount_code_id,
            ep.event_purchase_id,
            ep.user_id
        from event_purchase ep
        left join admission_offer ao
            on ao.admission_offer_id = ep.admission_offer_id
        where ep.event_id = p_event_id
        and ep.status = 'pending'
        and (
            ep.hold_expires_at <= current_timestamp
            or (
                ao.status in ('checkout_pending', 'pending')
                and ao.expires_at is not null
                and ao.expires_at <= current_timestamp
            )
        )
        order by ep.event_purchase_id
    loop
        update event_purchase
        set
            hold_expires_at = least(hold_expires_at, current_timestamp),
            status = 'expired',
            updated_at = current_timestamp
        where event_purchase_id = v_event_purchase.event_purchase_id
        and status = 'pending';

        if not found then
            continue;
        end if;

        if v_event_purchase.event_discount_code_id is not null then
            perform release_event_discount_code_availability(
                v_event_purchase.event_discount_code_id
            );
        end if;

        perform release_event_checkout_attendee_hold(
            p_event_id,
            v_event_purchase.user_id
        );
    end loop;

    -- Expire due offers or return abandoned checkout offers to pending
    for v_admission_offer in
        select
            ao.admission_offer_id,
            ao.expires_at,
            ao.status,
            ao.user_id
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.status in ('checkout_pending', 'pending')
        order by ao.admission_offer_id
    loop
        if v_admission_offer.expires_at is not null
           and v_admission_offer.expires_at <= current_timestamp then
            update admission_offer
            set
                status = 'expired',
                updated_at = current_timestamp
            where admission_offer_id = v_admission_offer.admission_offer_id
            and status = v_admission_offer.status;

            if found then
                perform insert_audit_log(
                    'admission_offer_expired',
                    null,
                    'admission_offer',
                    v_admission_offer.admission_offer_id,
                    v_community_id,
                    v_group_id,
                    p_event_id,
                    jsonb_build_object(
                        'admission_offer_id',
                        v_admission_offer.admission_offer_id,
                        'user_id',
                        v_admission_offer.user_id
                    )
                );
            end if;
        elsif v_admission_offer.status = 'checkout_pending'
              and not exists (
                    select 1
                    from event_purchase ep
                    where ep.admission_offer_id = v_admission_offer.admission_offer_id
                    and (
                        ep.status in (
                            'completed',
                            'refund-pending',
                            'refund-recovery-pending',
                            'refund-requested'
                        )
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

    -- Stop ticket offer creation when the public registration window is closed
    v_event_registration_open := is_registration_window_open(
        v_registration_starts_at,
        v_registration_ends_at,
        v_starts_at
    );

    if not v_event_active or not v_event_registration_open then
        return coalesce(v_promoted_user_ids, array[]::uuid[]);
    end if;

    -- Load the site theme once for promotion notifications
    select s.theme
    into v_theme
    from site s
    limit 1;

    -- Fill public tier capacity from each FIFO queue without skipping blocked heads
    for v_ticket_type in
        select
            ett.event_ticket_type_id,
            ett.seats_total,
            ett.title
        from event_ticket_type ett
        where ett.event_id = p_event_id
        and ett.active = true
        and ett.availability = 'public'
        and (
            p_event_ticket_type_id is null
            or ett.event_ticket_type_id = p_event_ticket_type_id
        )
        order by ett.event_ticket_type_id
    loop
        loop
            -- Stop when the tier has no remaining seats
            select get_event_ticket_type_allocated_seat_count(
                p_event_id,
                v_ticket_type.event_ticket_type_id
            )
            into v_allocated_seat_count;

            if v_allocated_seat_count >= v_ticket_type.seats_total then
                exit;
            end if;

            -- Lock the FIFO queue head for this tier
            select
                ew.created_at,
                ew.user_id
            into v_waitlist_entry
            from event_waitlist ew
            where ew.event_id = p_event_id
            and ew.event_ticket_type_id = v_ticket_type.event_ticket_type_id
            order by ew.created_at, ew.user_id
            for update of ew
            limit 1;

            if not found then
                exit;
            end if;

            -- Resolve current pricing before moving the queue head
            select etpw.amount_minor
            into v_price_amount_minor
            from event_ticket_price_window etpw
            where etpw.event_ticket_type_id = v_ticket_type.event_ticket_type_id
            and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
            and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
            order by
                etpw.starts_at desc nulls last,
                etpw.event_ticket_price_window_id
            limit 1;

            if not found then
                exit;
            end if;

            -- Keep a paid queue head in place until payment configuration is ready
            if v_price_amount_minor > 0
               and (
                    p_configured_provider is null
                    or v_payment_currency_code is null
                    or v_group_payment_recipient is null
                    or coalesce(v_group_payment_recipient->>'provider', '')
                        <> p_configured_provider
                    or nullif(
                        btrim(v_group_payment_recipient->>'recipient_id'),
                        ''
                    ) is null
               ) then
                exit;
            end if;

            -- Bound the offer lifetime by registration close and event start
            v_offer_expires_at := least(
                current_timestamp + interval '24 hours',
                coalesce(v_registration_ends_at, 'infinity'::timestamptz),
                coalesce(v_starts_at, 'infinity'::timestamptz)
            );

            if v_offer_expires_at <= current_timestamp then
                exit;
            end if;

            -- Move the queue head into a capacity-reserving offer
            delete from event_waitlist
            where event_id = p_event_id
            and user_id = v_waitlist_entry.user_id
            and event_ticket_type_id = v_ticket_type.event_ticket_type_id;

            if not found then
                continue;
            end if;

            insert into admission_offer (
                event_id,
                event_ticket_type_id,
                expires_at,
                source,
                status,
                user_id
            ) values (
                p_event_id,
                v_ticket_type.event_ticket_type_id,
                v_offer_expires_at,
                'waitlist',
                'pending',
                v_waitlist_entry.user_id
            )
            returning admission_offer_id into v_offer_id;

            -- Track and notify the promoted ticket recipient atomically
            perform insert_audit_log(
                'event_ticket_waitlist_offer_created',
                null,
                'admission_offer',
                v_offer_id,
                v_community_id,
                v_group_id,
                p_event_id,
                jsonb_build_object(
                    'admission_offer_id', v_offer_id,
                    'event_ticket_type_id', v_ticket_type.event_ticket_type_id,
                    'user_id', v_waitlist_entry.user_id
                )
            );

            perform enqueue_notification(
                'event-ticket-waitlist-offer',
                jsonb_build_object(
                    'admission_offer_id', v_offer_id,
                    'amount_minor', v_price_amount_minor,
                    'currency_code', v_payment_currency_code,
                    'dashboard_url', format(
                        '/dashboard/user?tab=invitations#event-offer-%s',
                        v_offer_id
                    ),
                    'event_id', p_event_id,
                    'event_name', v_event_name,
                    'event_ticket_type_id', v_ticket_type.event_ticket_type_id,
                    'expires_at', extract(epoch from v_offer_expires_at)::bigint,
                    'group_name', v_group_name,
                    'is_simple_rsvp', v_is_simple_rsvp,
                    'theme', v_theme,
                    'ticket_title', v_ticket_type.title,
                    'timezone', v_timezone,
                    'user_id', v_waitlist_entry.user_id
                ),
                '[]'::jsonb,
                array[v_waitlist_entry.user_id]
            );

            v_promoted_user_ids := array_append(
                v_promoted_user_ids,
                v_waitlist_entry.user_id
            );
        end loop;
    end loop;

    -- Return the users promoted from the queues
    return coalesce(v_promoted_user_ids, array[]::uuid[]);
end;
$$ language plpgsql;
