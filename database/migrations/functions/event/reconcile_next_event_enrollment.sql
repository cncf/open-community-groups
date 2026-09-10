-- Reconciles one event with due reservations or newly promotable ticket queues.
create or replace function reconcile_next_event_enrollment(
    p_configured_provider text default null
)
returns json as $$
declare
    v_community_id uuid;
    v_event_id uuid;
    v_group_id uuid;
begin
    -- Claim one due or newly promotable event without blocking another worker
    select
        g.community_id,
        e.event_id,
        e.group_id
    into
        v_community_id,
        v_event_id,
        v_group_id
    from event e
    join "group" g using (group_id)
    where (
        exists (
            select 1
            from admission_offer ao
            where ao.event_id = e.event_id
            and admission_offer_is_active(ao.status)
            and ao.expires_at is not null
            and ao.expires_at <= current_timestamp
        )
        or exists (
            select 1
            from event_purchase ep
            where ep.event_id = e.event_id
            and ep.status = 'pending'
            and (
                ep.hold_expires_at <= current_timestamp
                or (
                    ep.charge_model = 'external'
                    and ep.external_payment_reminder_sent_at is null
                    and ep.hold_expires_at is not null
                    and ep.created_at <= ep.hold_expires_at - interval '24 hours'
                    and ep.hold_expires_at - interval '24 hours' <= current_timestamp
                    and ep.hold_expires_at > current_timestamp
                )
            )
        )
        or (
            g.active = true
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and (e.starts_at is null or e.starts_at > current_timestamp)
            and is_registration_window_open(
                e.registration_starts_at,
                e.registration_ends_at,
                e.starts_at
            )
            and exists (
                select 1
                from event_waitlist ew
                join event_ticket_type ett
                    on ett.event_ticket_type_id = ew.event_ticket_type_id
                where ew.event_id = e.event_id
                and ett.active = true
                and ett.availability = 'public'
                and event_ticket_type_current_price(ett.event_ticket_type_id) is not null
                and get_event_ticket_type_allocated_seat_count(
                    e.event_id,
                    ett.event_ticket_type_id
                ) < ett.seats_total
                and (
                    event_ticket_type_current_price(ett.event_ticket_type_id) = 0
                    or (
                        e.external_payment_url is not null
                        and is_event_external_payments_ready(e.event_id)
                    )
                    or (
                        e.external_payment_url is null
                        and p_configured_provider is not null
                        and e.payment_currency_code is not null
                        and g.payment_recipient is not null
                        and coalesce(g.payment_recipient->>'provider', '')
                            = p_configured_provider
                        and nullif(
                            btrim(g.payment_recipient->>'recipient_id'),
                            ''
                        ) is not null
                    )
                )
            )
        )
    )
    order by e.event_id
    for update of e skip locked
    limit 1;

    if not found then
        return null;
    end if;

    -- Expire due reservations and fill the released capacity
    perform reconcile_event_enrollment(
        v_event_id,
        null,
        p_configured_provider
    );

    -- Return the reconciliation context used by notification workers
    return json_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id,
        'group_id', v_group_id
    );
end;
$$ language plpgsql;
