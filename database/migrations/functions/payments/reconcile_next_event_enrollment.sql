-- Reconciles one event with pending enrollment work, claiming the lowest event
-- id among events with admission offers past their deadline, pending holds that
-- expired or are due an external payment reminder, and queues whose public tiers
-- can promote a queue head now. A persistently failing event is retried first
-- after each error pause, which blocks worker-driven progress for higher event
-- ids until fixed, while inline reconciliation for those events still runs on
-- user actions.
create or replace function reconcile_next_event_enrollment(
    p_configured_provider text default null
)
returns json as $$
declare
    v_community_id uuid;
    v_event_id uuid;
    v_group_id uuid;
begin
    -- Claim one event with pending work without blocking another worker
    select
        g.community_id,
        e.event_id,
        e.group_id
    into
        v_community_id,
        v_event_id,
        v_group_id
    from (
        -- Events with admission offers past their deadline
        select ao.event_id
        from admission_offer ao
        where admission_offer_is_lapsed(ao.status, ao.expires_at)

        union

        -- Events with pending holds that expired or are due an external
        -- payment reminder
        select ep.event_id
        from event_purchase ep
        where ep.status = 'pending'
        and ep.hold_expires_at <= current_timestamp + interval '24 hours'
        and (
            ep.hold_expires_at <= current_timestamp
            or event_purchase_external_reminder_is_due(ep)
        )

        union

        -- Queued events whose public tiers can promote a queue head now
        select qe.event_id
        from event qe
        join "group" qg on qg.group_id = qe.group_id
        cross join lateral (
            select
                bool_or(tier.amount_minor = 0) as has_free_tier,
                max(tier.amount_minor) as max_amount_minor
            from (
                select distinct ew.event_ticket_type_id
                from event_waitlist ew
                where ew.event_id = qe.event_id
            ) waitlisted_tier
            join event_ticket_type ett
                on ett.event_ticket_type_id = waitlisted_tier.event_ticket_type_id
            cross join lateral (
                select event_ticket_type_current_price(ett.event_ticket_type_id)
                    as amount_minor
            ) tier
            where ett.active = true
            and ett.availability = 'public'
            and tier.amount_minor is not null
            and get_event_ticket_type_allocated_seat_count(
                qe.event_id,
                ett.event_ticket_type_id
            ) < ett.seats_total
        ) tiers
        where qe.event_id in (select ew.event_id from event_waitlist ew)
        and event_accepts_waitlist_promotion(qe, qg)
        and (
            tiers.has_free_tier
            or (
                -- Keep the guard false without promotable tiers to skip readiness
                coalesce(tiers.max_amount_minor, 0) > 0
                and is_admission_offer_payment_ready(
                    qe,
                    qg,
                    tiers.max_amount_minor,
                    p_configured_provider
                )
            )
        )
    ) candidate
    join event e on e.event_id = candidate.event_id
    join "group" g on g.group_id = e.group_id
    order by e.event_id
    for update of e skip locked
    limit 1;

    -- Report no work when no event needs reconciliation
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
