-- Fills the remaining capacity of the public active ticket tiers of an event
-- (or of one scoped tier) from each tier's FIFO waitlist, turning queue heads
-- into pending admission offers bounded by registration close and event
-- start. A queue head stays in place while its tier has no price or a paid
-- price cannot be collected yet. Returns the promoted user identifiers.
-- Callers hold the event enrollment locks and have verified the event accepts
-- enrollment.
create or replace function promote_event_waitlist_entries(
    p_event event,
    p_group "group",
    p_event_ticket_type_id uuid,
    p_configured_provider text,
    p_theme jsonb
)
returns uuid[] as $$
declare
    v_is_simple_rsvp boolean := is_event_simple_rsvp(p_event.event_id);
    v_offer_expires_at timestamptz;
    v_offer_id uuid;
    v_price_amount_minor bigint;
    v_promoted_user_ids uuid[] := array[]::uuid[];
    v_ticket_type event_ticket_type;
    v_waitlist_entry event_waitlist;
begin
    -- Fill public tier capacity from each FIFO queue without skipping blocked heads
    for v_ticket_type in
        select ett.*
        from event_ticket_type ett
        where ett.event_id = p_event.event_id
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
            if get_event_ticket_type_allocated_seat_count(p_event.event_id, v_ticket_type.event_ticket_type_id)
               >= v_ticket_type.seats_total then
                exit;
            end if;

            -- Lock the FIFO queue head for this tier
            select ew.*
            into v_waitlist_entry
            from event_waitlist ew
            where ew.event_id = p_event.event_id
            and ew.event_ticket_type_id = v_ticket_type.event_ticket_type_id
            order by ew.created_at, ew.user_id
            for update of ew
            limit 1;

            -- Stop when the queue is empty
            if not found then
                exit;
            end if;

            -- Keep the queue head in place while the tier has no active price
            v_price_amount_minor := event_ticket_type_current_price(v_ticket_type.event_ticket_type_id);
            if v_price_amount_minor is null then
                exit;
            end if;

            -- Keep a paid queue head in place until payment configuration is ready
            if v_price_amount_minor > 0 then
                -- External-marked events promote only while external payments remain ready
                if p_event.external_payment_url is not null then
                    -- Pause the queue head when the group is no longer eligible
                    if not is_event_external_payments_ready(p_event.event_id) then
                        exit;
                    end if;

                -- Stripe-marked events keep the provider-readiness gate
                elsif p_configured_provider is null
                   or p_event.payment_currency_code is null
                   or p_group.payment_recipient is null
                   or coalesce(p_group.payment_recipient->>'provider', '') <> p_configured_provider
                   or nullif(btrim(p_group.payment_recipient->>'recipient_id'), '') is null then
                    exit;
                end if;
            end if;

            -- Bound the offer lifetime by registration close and event start
            v_offer_expires_at := least(
                current_timestamp + interval '24 hours',
                coalesce(p_event.registration_ends_at, 'infinity'::timestamptz),
                coalesce(p_event.starts_at, 'infinity'::timestamptz)
            );

            -- Stop when an offer could not be claimed before it expired
            if v_offer_expires_at <= current_timestamp then
                exit;
            end if;

            -- Move the queue head into a capacity-reserving offer
            delete from event_waitlist
            where event_id = p_event.event_id
            and user_id = v_waitlist_entry.user_id
            and event_ticket_type_id = v_ticket_type.event_ticket_type_id;

            -- Skip queue heads removed by a concurrent transition
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
                p_event.event_id,
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
                p_group.community_id,
                p_event.group_id,
                p_event.event_id,
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
                    'currency_code', p_event.payment_currency_code,
                    'dashboard_url', format('/dashboard/user?tab=invitations#event-offer-%s', v_offer_id),
                    'event_id', p_event.event_id,
                    'event_name', p_event.name,
                    'event_ticket_type_id', v_ticket_type.event_ticket_type_id,
                    'expires_at', epoch_seconds(v_offer_expires_at),
                    'group_name', p_group.name,
                    'is_simple_rsvp', v_is_simple_rsvp,
                    'theme', p_theme,
                    'ticket_title', v_ticket_type.title,
                    'timezone', p_event.timezone,
                    'user_id', v_waitlist_entry.user_id
                ),
                '[]'::jsonb,
                array[v_waitlist_entry.user_id]
            );

            v_promoted_user_ids := array_append(v_promoted_user_ids, v_waitlist_entry.user_id);
        end loop;
    end loop;

    -- Return the users promoted from the queues
    return v_promoted_user_ids;
end;
$$ language plpgsql;
