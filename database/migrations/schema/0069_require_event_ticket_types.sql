-- Requires every event to use ticket-tier enrollment and synchronizes event capacity.
--
-- The migration runs as a single transaction and proceeds in five phases:
--
--   1. Snapshot: drop the admission-offer lifecycle trigger so legacy offers can
--      be rewritten, then record per-event occupied seats (confirmed attendees,
--      live offers, capacity-bearing purchases) before rewriting any enrollment
--      rows, for later capacity math and final verification.
--   2. Inventory: create a default free public "General Admission" tier for
--      events without ticket types, give each synthesized tier a free price
--      window, and map already-ticketed events to their first public tier.
--   3. Enrollment conversion: backfill free completed purchases for confirmed
--      attendees, convert unowned pending-question seats into bounded admission
--      offers, rewrite legacy offers into the new shape, scope waitlist entries
--      and approval requests to the migration tier, and expand any tier left
--      oversubscribed by the backfill.
--   4. Constraints: require a ticket tier on every offer and waitlist entry,
--      drop the legacy offer shape, require a bounded deadline on every offer,
--      recreate the offer lifecycle trigger, require at least one ticket type
--      per event at commit, and keep event capacity in sync with ticket tiers.
--   5. Verification and cleanup: abort the whole transaction if any occupied
--      seat was lost, moved across tiers, or oversubscribed, then drop the
--      functions of the superseded non-ticketed enrollment model.

-- Allow legacy admission offers to receive immutable tier and deadline fields.
drop trigger admission_offer_lifecycle_check on admission_offer;

-- Snapshot occupied seats before changing any enrollment representation.
create temporary table event_ticket_migration on commit drop as
with occupied_users as (
    select ea.event_id, ea.user_id
    from event_attendee ea
    where ea.status in ('confirmed', 'registration-questions-pending')

    union

    select ao.event_id, ao.user_id
    from admission_offer ao
    where ao.status in ('checkout_pending', 'pending')

    union

    select ep.event_id, ep.user_id
    from event_purchase ep
    where ep.status in (
        'completed',
        'refund-pending',
        'refund-recovery-pending',
        'refund-requested'
    )
    or (
        ep.status = 'pending'
        and ep.hold_expires_at > current_timestamp
    )
),
occupied_counts as (
    select ou.event_id, count(*)::int as occupied_count
    from occupied_users ou
    group by ou.event_id
),
expected_occupied_users as (
    select ea.event_id, ea.user_id
    from event_attendee ea
    join event e using (event_id)
    where ea.status = 'confirmed'
    or (
        ea.status = 'registration-questions-pending'
        and (
            exists (
                select 1
                from event_purchase ep
                where ep.event_id = ea.event_id
                and ep.user_id = ea.user_id
                and ep.status = 'pending'
                and ep.hold_expires_at > current_timestamp
            )
            or least(
                current_timestamp + interval '24 hours',
                coalesce(e.registration_ends_at, 'infinity'::timestamptz),
                coalesce(e.starts_at, 'infinity'::timestamptz)
            ) > current_timestamp
        )
    )

    union

    select ao.event_id, ao.user_id
    from admission_offer ao
    join event e using (event_id)
    where ao.status in ('checkout_pending', 'pending')
    and (
        ao.legacy = false
        or case
            when e.starts_at is not null and e.starts_at > current_timestamp
                then least(current_timestamp + interval '24 hours', e.starts_at)
            else least(
                current_timestamp + interval '24 hours',
                coalesce(e.ends_at, 'infinity'::timestamptz)
            )
        end > current_timestamp
    )

    union

    select ep.event_id, ep.user_id
    from event_purchase ep
    where ep.status in (
        'completed',
        'refund-pending',
        'refund-recovery-pending',
        'refund-requested'
    )
    or (
        ep.status = 'pending'
        and ep.hold_expires_at > current_timestamp
    )
),
expected_occupied_counts as (
    select eou.event_id, count(*)::int as occupied_count
    from expected_occupied_users eou
    group by eou.event_id
)
select
    e.event_id,
    exists (
        select 1
        from event_ticket_type ett
        where ett.event_id = e.event_id
    ) as had_ticket_types,
    coalesce(oc.occupied_count, 0) as occupied_count_before,
    coalesce(eoc.occupied_count, 0) as occupied_count_expected,
    null::uuid as event_ticket_type_id
from event e
left join occupied_counts oc using (event_id)
left join expected_occupied_counts eoc using (event_id);

-- Create a default free public tier for events without ticket inventory.
with inserted_ticket_types as (
    insert into event_ticket_type (
        event_ticket_type_id,
        active,
        availability,
        event_id,
        "order",
        seats_total,
        title
    )
    select
        gen_random_uuid(),
        true,
        'public',
        e.event_id,
        1,
        case
            when e.capacity is null
                then greatest(etm.occupied_count_expected, 500)
            else greatest(e.capacity, etm.occupied_count_expected)
        end,
        'General Admission'
    from event e
    join event_ticket_migration etm using (event_id)
    where not exists (
        select 1
        from event_ticket_type ett
        where ett.event_id = e.event_id
    )
    returning event_id, event_ticket_type_id
)
update event_ticket_migration etm
set event_ticket_type_id = itt.event_ticket_type_id
from inserted_ticket_types itt
where itt.event_id = etm.event_id;

-- Give every synthesized tier one open-ended free price window.
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
)
select
    gen_random_uuid(),
    0,
    etm.event_ticket_type_id
from event_ticket_migration etm
where etm.had_ticket_types = false
and etm.event_ticket_type_id is not null;

-- Map already-ticketed events to their first public tier or first tier overall.
update event_ticket_migration etm
set event_ticket_type_id = (
    select ett.event_ticket_type_id
    from event_ticket_type ett
    where ett.event_id = etm.event_id
    order by
        (ett.availability = 'public') desc,
        ett."order",
        ett.event_ticket_type_id
    limit 1
)
where etm.event_ticket_type_id is null;

-- Give every confirmed attendee exactly one capacity-owning ticket purchase.
insert into event_purchase (
    amount_minor,
    completed_at,
    created_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    updated_at,
    user_id
)
select
    0,
    ea.created_at,
    ea.created_at,
    null,
    0,
    ea.event_id,
    etm.event_ticket_type_id,
    'completed',
    ett.title,
    ea.created_at,
    ea.user_id
from event_attendee ea
join event_ticket_migration etm using (event_id)
join event_ticket_type ett using (event_ticket_type_id)
where ea.status = 'confirmed'
and not exists (
    select 1
    from event_purchase ep
    where ep.event_id = ea.event_id
    and ep.user_id = ea.user_id
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
);

-- Convert unowned pending-question seats into bounded admission offers.
with pending_attendees as (
    delete from event_attendee ea
    where ea.status = 'registration-questions-pending'
    and not exists (
        select 1
        from event_purchase ep
        where ep.event_id = ea.event_id
        and ep.user_id = ea.user_id
        and ep.status = 'pending'
        and ep.hold_expires_at > current_timestamp
    )
    returning ea.created_at, ea.event_id, ea.user_id
),
offer_context as (
    select
        pa.created_at,
        pa.event_id,
        etm.event_ticket_type_id,
        least(
            current_timestamp + interval '24 hours',
            coalesce(e.registration_ends_at, 'infinity'::timestamptz),
            coalesce(e.starts_at, 'infinity'::timestamptz)
        ) as active_expires_at,
        pa.user_id
    from pending_attendees pa
    join event e using (event_id)
    join event_ticket_migration etm using (event_id)
)
insert into admission_offer (
    amount_minor,
    created_at,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    updated_at,
    user_id
)
select
    0,
    oc.created_at,
    0,
    oc.event_id,
    oc.event_ticket_type_id,
    case
        when oc.active_expires_at > current_timestamp then oc.active_expires_at
        else greatest(
            oc.created_at + interval '24 hours',
            oc.created_at + interval '1 second'
        )
    end,
    'waitlist',
    case
        when oc.active_expires_at > current_timestamp then 'pending'
        else 'expired'
    end,
    ett.title,
    current_timestamp,
    oc.user_id
from offer_context oc
join event_ticket_type ett using (event_ticket_type_id)
where not exists (
    select 1
    from admission_offer ao
    where ao.event_id = oc.event_id
    and ao.user_id = oc.user_id
    and ao.status in ('checkout_pending', 'pending')
);

-- Backfill every legacy offer with a tier, complete free snapshot, and deadline.
with legacy_offer_context as (
    select
        ao.admission_offer_id,
        case
            when e.starts_at is not null and e.starts_at > current_timestamp
                then least(current_timestamp + interval '24 hours', e.starts_at)
            else least(
                current_timestamp + interval '24 hours',
                coalesce(e.ends_at, 'infinity'::timestamptz)
            )
        end as active_expires_at,
        etm.event_ticket_type_id,
        ett.title
    from admission_offer ao
    join event e using (event_id)
    join event_ticket_migration etm using (event_id)
    join event_ticket_type ett
        on ett.event_ticket_type_id = etm.event_ticket_type_id
    where ao.legacy = true
)
update admission_offer ao
set
    amount_minor = 0,
    currency_code = null,
    discount_amount_minor = 0,
    discount_code = null,
    event_discount_code_id = null,
    event_ticket_type_id = loc.event_ticket_type_id,
    expires_at = case
        when ao.status in ('checkout_pending', 'pending')
             and loc.active_expires_at > current_timestamp
            then loc.active_expires_at
        else greatest(
            ao.created_at + interval '24 hours',
            ao.created_at + interval '1 second'
        )
    end,
    legacy = false,
    status = case
        when ao.status in ('checkout_pending', 'pending')
             and loc.active_expires_at <= current_timestamp
            then 'expired'
        else ao.status
    end,
    ticket_title = loc.title,
    updated_at = current_timestamp
from legacy_offer_context loc
where loc.admission_offer_id = ao.admission_offer_id;

-- Scope every waitlist and approval request to its event migration tier.
update event_invitation_request eir
set event_ticket_type_id = etm.event_ticket_type_id
from event_ticket_migration etm
join event_ticket_type ett using (event_ticket_type_id)
where eir.event_id = etm.event_id
and eir.event_ticket_type_id is null
and ett.availability = 'public';

update event_waitlist ew
set event_ticket_type_id = etm.event_ticket_type_id
from event_ticket_migration etm
where ew.event_id = etm.event_id
and ew.event_ticket_type_id is null;

-- Preserve every existing allocation by expanding a mapped tier when needed.
with tier_allocations as (
    select
        ett.event_ticket_type_id,
        (
            select count(*)
            from admission_offer ao
            where ao.event_id = ett.event_id
            and ao.event_ticket_type_id = ett.event_ticket_type_id
            and ao.status in ('checkout_pending', 'pending')
        ) + (
            select count(distinct coalesce(ep.admission_offer_id, ep.event_purchase_id))
            from event_purchase ep
            where ep.event_id = ett.event_id
            and ep.event_ticket_type_id = ett.event_ticket_type_id
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
            and not exists (
                select 1
                from admission_offer ao
                where ao.admission_offer_id = ep.admission_offer_id
                and ao.status in ('checkout_pending', 'pending')
            )
        ) as allocated_count
    from event_ticket_type ett
)
update event_ticket_type ett
set seats_total = ta.allocated_count
from tier_allocations ta
where ta.event_ticket_type_id = ett.event_ticket_type_id
and ta.allocated_count > ett.seats_total;

-- Require every migrated offer and waitlist entry to identify its ticket tier.
alter table admission_offer
    alter column event_ticket_type_id set not null;

alter table event_waitlist
    alter column event_ticket_type_id set not null;

-- Remove the legacy offer shape and require a bounded deadline for every offer.
alter table admission_offer
    drop constraint admission_offer_deadline_chk,
    drop column legacy,
    add constraint admission_offer_deadline_chk check (
        expires_at is not null
        and expires_at > created_at
    );

-- Preserves offer ownership, first-claim snapshots, and legal status transitions.
create or replace function check_admission_offer_lifecycle()
returns trigger as $$
begin
    -- Keep offer ownership and deadline identity immutable
    if row(
        new.created_at,
        new.event_id,
        new.event_ticket_type_id,
        new.expires_at,
        new.organizer_user_id,
        new.source,
        new.user_id
    ) is distinct from row(
        old.created_at,
        old.event_id,
        old.event_ticket_type_id,
        old.expires_at,
        old.organizer_user_id,
        old.source,
        old.user_id
    ) then
        raise exception 'admission offer ownership and deadline fields are immutable';
    end if;

    -- Preserve the first claim-time price snapshot across checkout retries
    if old.amount_minor is not null
       and row(
            new.amount_minor,
            new.currency_code,
            new.discount_amount_minor,
            new.discount_code,
            new.event_discount_code_id,
            new.ticket_title
       ) is distinct from row(
            old.amount_minor,
            old.currency_code,
            old.discount_amount_minor,
            old.discount_code,
            old.event_discount_code_id,
            old.ticket_title
       ) then
        raise exception 'admission offer price snapshot is immutable';
    end if;

    -- Enforce the offer lifecycle while permitting idempotent same-state updates
    if new.status <> old.status
       and not (
            (old.status = 'pending' and new.status in (
                'canceled',
                'checkout_pending',
                'completed',
                'declined',
                'expired'
            ))
            or (
                old.status = 'checkout_pending'
                and new.status in (
                    'canceled',
                    'completed',
                    'declined',
                    'expired',
                    'pending'
                )
            )
       ) then
        raise exception 'invalid admission offer status transition: % -> %', old.status, new.status;
    end if;

    return new;
end;
$$ language plpgsql;

-- Enforce admission-offer lifecycle invariants on every update.
create trigger admission_offer_lifecycle_check
    before update on admission_offer
    for each row
    execute function check_admission_offer_lifecycle();

-- The universal ticket invariant supersedes the old waitlist-only capacity guard.
drop trigger if exists event_waitlist_capacity_required_on_event on event;
drop trigger if exists event_waitlist_capacity_required_on_event_ticket_type on event_ticket_type;
drop function if exists check_event_waitlist_capacity_required();

-- Requires every persisted event to own at least one ticket type at commit.
create or replace function check_event_has_ticket_type()
returns trigger as $$
declare
    v_event_id uuid;
    v_event_ids uuid[];
begin
    -- Resolve every event affected by an event or ticket-type write
    if tg_table_name = 'event' then
        v_event_ids := array[new.event_id];
    elsif tg_op = 'INSERT' then
        v_event_ids := array[new.event_id];
    elsif tg_op = 'DELETE' then
        v_event_ids := array[old.event_id];
    else
        v_event_ids := array[old.event_id, new.event_id];
    end if;

    -- Validate the settled ticket inventory for each surviving event
    foreach v_event_id in array v_event_ids
    loop
        if exists (
            select 1
            from event e
            where e.event_id = v_event_id
        )
        and not exists (
            select 1
            from event_ticket_type ett
            where ett.event_id = v_event_id
        ) then
            raise exception 'events require at least one ticket type';
        end if;
    end loop;

    return null;
end;
$$ language plpgsql;

-- Enforce ticket inventory after event and ticket-tier writes settle.
create constraint trigger event_has_ticket_type_on_event
    after insert on event
    deferrable initially deferred
    for each row
    execute function check_event_has_ticket_type();

create constraint trigger event_has_ticket_type_on_event_ticket_type
    after insert or update or delete on event_ticket_type
    deferrable initially deferred
    for each row
    execute function check_event_has_ticket_type();

-- Maintains event capacity after locking affected events in stable order.
create or replace function sync_event_capacity_from_ticket_types()
returns trigger as $$
declare
    v_event_id uuid;
begin
    -- Lock before aggregating so a waiter sees concurrent committed tier writes
    if tg_op = 'INSERT' then
        -- Recompute capacity for events that received new tiers
        for v_event_id in
            select ntt.event_id
            from new_ticket_types ntt
            group by ntt.event_id
            order by ntt.event_id
        loop
            perform 1
            from event
            where event_id = v_event_id
            for no key update;

            update event e
            set capacity = coalesce((
                select sum(ett.seats_total)::int
                from event_ticket_type ett
                where ett.event_id = v_event_id
            ), 0)
            where e.event_id = v_event_id;
        end loop;
    elsif tg_op = 'DELETE' then
        -- Recompute capacity for events that lost tiers
        for v_event_id in
            select ott.event_id
            from old_ticket_types ott
            group by ott.event_id
            order by ott.event_id
        loop
            perform 1
            from event
            where event_id = v_event_id
            for no key update;

            update event e
            set capacity = coalesce((
                select sum(ett.seats_total)::int
                from event_ticket_type ett
                where ett.event_id = v_event_id
            ), 0)
            where e.event_id = v_event_id;
        end loop;
    else
        -- Recompute capacity for events touched on either side of an update
        for v_event_id in
            with affected_events as (
                select ntt.event_id
                from new_ticket_types ntt

                union all

                select ott.event_id
                from old_ticket_types ott
            )
            select ae.event_id
            from affected_events ae
            group by ae.event_id
            order by ae.event_id
        loop
            perform 1
            from event
            where event_id = v_event_id
            for no key update;

            update event e
            set capacity = coalesce((
                select sum(ett.seats_total)::int
                from event_ticket_type ett
                where ett.event_id = v_event_id
            ), 0)
            where e.event_id = v_event_id;
        end loop;
    end if;

    return null;
end;
$$ language plpgsql;

-- Align existing event capacity with the migrated ticket inventory.
update event e
set capacity = ticket_capacity.capacity
from (
    select ett.event_id, sum(ett.seats_total)::int as capacity
    from event_ticket_type ett
    group by ett.event_id
) ticket_capacity
where ticket_capacity.event_id = e.event_id;

-- Keep event capacity synchronized after ticket-tier writes.
create trigger event_capacity_sync_after_delete
    after delete on event_ticket_type
    referencing old table as old_ticket_types
    for each statement
    execute function sync_event_capacity_from_ticket_types();

create trigger event_capacity_sync_after_insert
    after insert on event_ticket_type
    referencing new table as new_ticket_types
    for each statement
    execute function sync_event_capacity_from_ticket_types();

create trigger event_capacity_sync_after_update
    after update on event_ticket_type
    referencing old table as old_ticket_types new table as new_ticket_types
    for each statement
    execute function sync_event_capacity_from_ticket_types();

-- Abort before removing old entry points if the converted enrollment is unsafe.
do $$
begin
    -- Verify confirmed attendees own exactly one capacity-bearing purchase
    if exists (
        select 1
        from event_attendee ea
        where ea.status = 'confirmed'
        and (
            select count(*)
            from event_purchase ep
            join event_ticket_type ett
                on ett.event_id = ep.event_id
                and ett.event_ticket_type_id = ep.event_ticket_type_id
            where ep.event_id = ea.event_id
            and ep.user_id = ea.user_id
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
        ) <> 1
    ) then
        raise exception 'migration left a confirmed attendee without exactly one ticket purchase';
    end if;

    -- Verify every capacity-bearing row belongs to its event and tier
    if exists (
        select 1
        from admission_offer ao
        left join event_ticket_type ett
            on ett.event_id = ao.event_id
            and ett.event_ticket_type_id = ao.event_ticket_type_id
        where ao.status in ('checkout_pending', 'pending')
        and ett.event_ticket_type_id is null
    ) or exists (
        select 1
        from event_purchase ep
        left join event_ticket_type ett
            on ett.event_id = ep.event_id
            and ett.event_ticket_type_id = ep.event_ticket_type_id
        where (
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
        and ett.event_ticket_type_id is null
    ) or exists (
        select 1
        from event_invitation_request eir
        left join event_ticket_type ett
            on ett.event_id = eir.event_id
            and ett.event_ticket_type_id = eir.event_ticket_type_id
        where eir.event_ticket_type_id is not null
        and ett.event_ticket_type_id is null
    ) or exists (
        select 1
        from event_waitlist ew
        left join event_ticket_type ett
            on ett.event_id = ew.event_id
            and ett.event_ticket_type_id = ew.event_ticket_type_id
        where ett.event_ticket_type_id is null
    ) then
        raise exception 'migration left enrollment assigned to another event ticket tier';
    end if;

    -- Verify allocation totals match distinct occupied users for every event
    if exists (
        with tier_allocations as (
            select
                ett.event_id,
                (
                    select count(*)
                    from admission_offer ao
                    where ao.event_id = ett.event_id
                    and ao.event_ticket_type_id = ett.event_ticket_type_id
                    and ao.status in ('checkout_pending', 'pending')
                ) + (
                    select count(distinct coalesce(ep.admission_offer_id, ep.event_purchase_id))
                    from event_purchase ep
                    where ep.event_id = ett.event_id
                    and ep.event_ticket_type_id = ett.event_ticket_type_id
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
                    and not exists (
                        select 1
                        from admission_offer ao
                        where ao.admission_offer_id = ep.admission_offer_id
                        and ao.status in ('checkout_pending', 'pending')
                    )
                ) as allocated_count
            from event_ticket_type ett
        ),
        event_allocations as (
            select ta.event_id, sum(ta.allocated_count)::int as allocated_count
            from tier_allocations ta
            group by ta.event_id
        ),
        occupied_users as (
            select ea.event_id, ea.user_id
            from event_attendee ea
            where ea.status = 'confirmed'

            union

            select ao.event_id, ao.user_id
            from admission_offer ao
            where ao.status in ('checkout_pending', 'pending')

            union

            select ep.event_id, ep.user_id
            from event_purchase ep
            where ep.status in (
                'completed',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
            or (
                ep.status = 'pending'
                and ep.hold_expires_at > current_timestamp
            )
        ),
        occupied_counts as (
            select ou.event_id, count(*)::int as occupied_count
            from occupied_users ou
            group by ou.event_id
        )
        select 1
        from event e
        left join event_allocations ea using (event_id)
        left join occupied_counts oc using (event_id)
        where coalesce(ea.allocated_count, 0) <> coalesce(oc.occupied_count, 0)
    ) then
        raise exception 'migration ticket allocations do not match occupied seats';
    end if;

    -- Verify no ticket tier is oversubscribed
    if exists (
        select 1
        from event_ticket_type ett
        where (
            select count(*)
            from admission_offer ao
            where ao.event_id = ett.event_id
            and ao.event_ticket_type_id = ett.event_ticket_type_id
            and ao.status in ('checkout_pending', 'pending')
        ) + (
            select count(distinct coalesce(ep.admission_offer_id, ep.event_purchase_id))
            from event_purchase ep
            where ep.event_id = ett.event_id
            and ep.event_ticket_type_id = ett.event_ticket_type_id
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
            and not exists (
                select 1
                from admission_offer ao
                where ao.admission_offer_id = ep.admission_offer_id
                and ao.status in ('checkout_pending', 'pending')
            )
        ) > ett.seats_total
    ) then
        raise exception 'migration oversubscribed an event ticket tier';
    end if;

    -- Verify post-migration occupancy matches the planned pre-migration snapshot
    if exists (
        with occupied_users as (
            select ea.event_id, ea.user_id
            from event_attendee ea
            where ea.status = 'confirmed'

            union

            select ao.event_id, ao.user_id
            from admission_offer ao
            where ao.status in ('checkout_pending', 'pending')

            union

            select ep.event_id, ep.user_id
            from event_purchase ep
            where ep.status in (
                'completed',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
            or (
                ep.status = 'pending'
                and ep.hold_expires_at > current_timestamp
            )
        ),
        occupied_counts as (
            select ou.event_id, count(*)::int as occupied_count
            from occupied_users ou
            group by ou.event_id
        )
        select 1
        from event_ticket_migration etm
        left join occupied_counts oc using (event_id)
        where coalesce(oc.occupied_count, 0) <> etm.occupied_count_expected
    ) then
        raise exception 'migration changed the expected occupied seat count';
    end if;
end;
$$;

-- Remove functions that expose or mutate the superseded enrollment model.
drop function if exists accept_event_admission_offer(uuid, uuid, jsonb, text);
drop function if exists accept_event_attendee_invitation(uuid, uuid, jsonb, text);
drop function if exists attend_event(uuid, uuid, uuid, jsonb, uuid);
drop function if exists cancel_event_admission_offer(uuid, uuid, uuid, text);
drop function if exists cancel_event_attendee_invitation(uuid, uuid, uuid, uuid, text);
drop function if exists complete_non_ticketed_event_admission_offer(uuid, uuid, uuid, jsonb, uuid);
drop function if exists decline_event_admission_offer(uuid, uuid, text);
drop function if exists get_event_attendance(uuid, uuid, uuid);
drop function if exists promote_event_waitlist(uuid, int);
drop function if exists reject_event_attendee_invitation(uuid, uuid, text);
drop function if exists release_event_admission_offer(uuid, text, uuid, uuid, text);
drop function if exists submit_event_registration_answers(uuid, uuid, uuid, jsonb);
drop function if exists update_event(uuid, uuid, uuid, jsonb, jsonb, text);
