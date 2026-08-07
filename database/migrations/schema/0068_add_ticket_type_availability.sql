-- Adds ticket availability, admission offers, and provider-free ticketing contracts.

alter table event_ticket_type
    add column availability text default 'public' not null,
    add constraint event_ticket_type_availability_chk check (
        availability = any(array['invitation_only', 'public']::text[])
    );

-- Store capacity-reserving admission offers across enrollment workflows.
create table admission_offer (
    admission_offer_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    event_id uuid not null references event,
    legacy boolean default false not null,
    source text not null,
    status text not null,
    updated_at timestamptz default current_timestamp not null,
    user_id uuid not null references "user",

    amount_minor bigint check (amount_minor is null or amount_minor >= 0),
    currency_code text check (currency_code is null or btrim(currency_code) <> ''),
    discount_amount_minor bigint check (
        discount_amount_minor is null or discount_amount_minor >= 0
    ),
    discount_code text check (discount_code is null or btrim(discount_code) <> ''),
    event_discount_code_id uuid references event_discount_code,
    event_ticket_type_id uuid references event_ticket_type,
    expires_at timestamptz,
    organizer_user_id uuid references "user",
    ticket_title text check (ticket_title is null or btrim(ticket_title) <> ''),

    constraint admission_offer_admission_offer_id_event_id_user_id_key
        unique (admission_offer_id, event_id, user_id),
    constraint admission_offer_deadline_chk check (
        (
            legacy = true
            and source = 'organizer_invitation'
            and expires_at is null
        )
        or (
            legacy = false
            and expires_at is not null
            and expires_at > created_at
        )
    ),
    constraint admission_offer_event_discount_code_belongs_to_event_fkey
        foreign key (event_id, event_discount_code_id)
            references event_discount_code (event_id, event_discount_code_id),
    constraint admission_offer_event_ticket_type_belongs_to_event_fkey
        foreign key (event_id, event_ticket_type_id)
            references event_ticket_type (event_id, event_ticket_type_id),
    constraint admission_offer_snapshot_chk check (
        (
            amount_minor is null
            and currency_code is null
            and discount_amount_minor is null
            and discount_code is null
            and event_discount_code_id is null
            and ticket_title is null
        )
        or (
            event_ticket_type_id is not null
            and amount_minor is not null
            and discount_amount_minor is not null
            and ticket_title is not null
            and (
                (
                    amount_minor = 0
                    and discount_amount_minor = 0
                    and currency_code is null
                )
                or (
                    currency_code is not null
                    and (amount_minor > 0 or discount_amount_minor > 0)
                )
            )
            and (
                (
                    discount_amount_minor = 0
                    and discount_code is null
                    and event_discount_code_id is null
                )
                or (
                    discount_amount_minor > 0
                    and discount_code is not null
                    and event_discount_code_id is not null
                )
            )
        )
    ),
    constraint admission_offer_source_chk check (
        source = any(array['approval', 'organizer_invitation', 'waitlist']::text[])
    ),
    constraint admission_offer_status_chk check (
        status = any(array[
            'canceled',
            'checkout_pending',
            'completed',
            'declined',
            'expired',
            'pending'
        ]::text[])
    ),
    constraint admission_offer_ticket_status_snapshot_chk check (
        event_ticket_type_id is null
        or status not in ('checkout_pending', 'completed')
        or amount_minor is not null
    )
);

create index admission_offer_due_idx
    on admission_offer (expires_at, admission_offer_id)
    where expires_at is not null
    and status = any(array['checkout_pending', 'pending']::text[]);
create index admission_offer_event_id_event_ticket_type_id_active_idx
    on admission_offer (event_id, event_ticket_type_id, created_at, admission_offer_id)
    where status = any(array['checkout_pending', 'pending']::text[]);
create index admission_offer_event_id_source_created_at_idx
    on admission_offer (event_id, source, created_at, admission_offer_id);
create unique index admission_offer_event_id_user_id_active_idx
    on admission_offer (event_id, user_id)
    where status = any(array['checkout_pending', 'pending']::text[]);
create index admission_offer_user_id_event_id_created_at_idx
    on admission_offer (user_id, event_id, created_at desc, admission_offer_id desc);

-- Scope waitlists and approval requests to an optional ticket tier.
alter table event_invitation_request
    add column event_ticket_type_id uuid references event_ticket_type,
    add constraint event_invitation_request_ticket_type_belongs_to_event_fkey
        foreign key (event_id, event_ticket_type_id)
            references event_ticket_type (event_id, event_ticket_type_id);

create index event_invitation_request_event_ticket_type_status_created_idx
    on event_invitation_request (event_id, event_ticket_type_id, status, created_at)
    where event_ticket_type_id is not null;

alter table event_waitlist
    add column event_ticket_type_id uuid references event_ticket_type,
    add constraint event_waitlist_event_ticket_type_belongs_to_event_fkey
        foreign key (event_id, event_ticket_type_id)
            references event_ticket_type (event_id, event_ticket_type_id);

create index event_waitlist_event_id_event_ticket_type_id_created_at_idx
    on event_waitlist (event_id, event_ticket_type_id, created_at, user_id)
    where event_ticket_type_id is not null;

-- Allow currency-free purchase snapshots only for intrinsic zero-price checkouts.
alter table event_purchase
    add column admission_offer_id uuid,
    alter column currency_code drop not null,
    drop constraint event_purchase_currency_code_check,
    add constraint event_purchase_admission_offer_belongs_to_event_user_fkey
        foreign key (admission_offer_id, event_id, user_id)
            references admission_offer (admission_offer_id, event_id, user_id),
    add constraint event_purchase_currency_code_chk check (
        (
            currency_code is not null
            and btrim(currency_code) <> ''
        )
        or (
            currency_code is null
            and amount_minor = 0
            and discount_amount_minor = 0
            and discount_code is null
            and event_discount_code_id is null
            and payment_provider_id is null
            and provider_checkout_session_id is null
            and provider_checkout_url is null
            and provider_payment_reference is null
        )
    );

-- Add offer retry uniqueness while preserving direct refund replacement behavior.
drop index event_purchase_event_id_user_id_active_idx;

create index event_purchase_admission_offer_id_created_at_idx
    on event_purchase (admission_offer_id, created_at desc)
    where admission_offer_id is not null;
create unique index event_purchase_admission_offer_id_active_idx
    on event_purchase (admission_offer_id)
    where admission_offer_id is not null
    and status = any(array[
        'completed',
        'pending',
        'refund-requested'
    ]::text[]);
create unique index event_purchase_event_id_user_id_active_idx
    on event_purchase (event_id, user_id)
    where status = any(array[
        'completed',
        'pending',
        'refund-requested'
    ]::text[]);

-- Replace enrollment mutations with provider-aware reconciliation boundaries.
drop function if exists accept_event_attendee_invitation(uuid, uuid);
drop function if exists accept_event_invitation_request(uuid, uuid, uuid, uuid);
drop function if exists attend_event(uuid, uuid, uuid, jsonb);
drop function if exists cancel_event_attendee_attendance(uuid, uuid, uuid, uuid);
drop function if exists cancel_event_attendee_invitation(uuid, uuid, uuid, uuid);
drop function if exists cancel_event_checkout(uuid, uuid, uuid);
drop function if exists complete_event_purchase_refund_recovery(
    uuid,
    uuid,
    uuid,
    text,
    text,
    jsonb
);
drop function if exists complete_non_ticketed_event_admission_offer(uuid, uuid, uuid, jsonb);
drop function if exists finalize_event_purchase_refund(uuid, uuid, jsonb);
drop function if exists invite_event_attendee(uuid, uuid, uuid, uuid, text);
drop function if exists leave_event(uuid, uuid, uuid);
drop function if exists prepare_event_checkout_find_existing_purchase(uuid, uuid, uuid, text);
drop function if exists prepare_event_checkout_purchase(uuid, uuid, uuid, uuid, text, text, jsonb);
drop function if exists prepare_event_checkout_validate_and_resolve_pricing(uuid, uuid, uuid, text);
drop function if exists reject_event_attendee_invitation(uuid, uuid);

-- Allow ticketed waitlists without requiring an event-level capacity.
alter table event
    drop constraint event_waitlist_capacity_required_chk;

create or replace function check_event_waitlist_capacity_required()
returns trigger as $$
declare
    v_capacity int;
    v_event_id uuid;
    v_event_ids uuid[];
    v_waitlist_enabled boolean;
begin
    -- Resolve every affected event after event or ticket-type changes
    if tg_table_name not in ('event', 'event_ticket_type') then
        raise exception 'unsupported waitlist capacity trigger table: %', tg_table_name;
    end if;

    if tg_op = 'INSERT' then
        v_event_ids := array[new.event_id];
    elsif tg_op = 'DELETE' then
        v_event_ids := array[old.event_id];
    else
        v_event_ids := array[old.event_id, new.event_id];
    end if;

    -- Validate settled event-level and ticketed waitlist configuration
    foreach v_event_id in array coalesce(v_event_ids, array[]::uuid[])
    loop
        if v_event_id is null then
            continue;
        end if;

        select
            e.capacity,
            e.waitlist_enabled
        into
            v_capacity,
            v_waitlist_enabled
        from event e
        where e.event_id = v_event_id;

        if not found then
            continue;
        end if;

        if v_waitlist_enabled
           and v_capacity is null
           and not exists (
                select 1
                from event_ticket_type ett
                where ett.event_id = v_event_id
           ) then
            raise exception 'waitlist enabled events must define a capacity or ticket types';
        end if;
    end loop;

    return null;
end;
$$ language plpgsql;

create constraint trigger event_waitlist_capacity_required_on_event
    after insert or update of capacity, waitlist_enabled on event
    deferrable initially deferred
    for each row
    execute function check_event_waitlist_capacity_required();

create constraint trigger event_waitlist_capacity_required_on_event_ticket_type
    after insert or update or delete on event_ticket_type
    deferrable initially deferred
    for each row
    execute function check_event_waitlist_capacity_required();

-- Convert pending legacy organizer invitations into open-ended offers.
create or replace function migrate_legacy_event_attendee_invitations()
returns int as $$
declare
    v_migrated_count int;
begin
    -- Move active legacy invitation rows into grandfathered offers atomically
    with legacy_invitations as (
        delete from event_attendee ea
        where ea.manually_invited = true
        and ea.status in ('invitation-pending', 'registration-questions-pending')
        and not exists (
            select 1
            from admission_offer ao
            where ao.event_id = ea.event_id
            and ao.source = 'organizer_invitation'
            and ao.status in ('checkout_pending', 'pending')
            and ao.user_id = ea.user_id
        )
        returning
            ea.created_at,
            ea.event_id,
            ea.user_id
    ),
    inserted_offers as (
        insert into admission_offer (
            created_at,
            event_id,
            legacy,
            source,
            status,
            updated_at,
            user_id,

            expires_at,
            organizer_user_id
        )
        select
            li.created_at,
            li.event_id,
            true,
            'organizer_invitation',
            'pending',
            li.created_at,
            li.user_id,

            null,
            invitation_audit.actor_user_id
        from legacy_invitations li
        left join lateral (
            select al.actor_user_id
            from audit_log al
            where al.action = 'event_attendee_invitation_sent'
            and al.event_id = li.event_id
            and al.resource_id = li.user_id
            and al.resource_type = 'user'
            order by al.created_at desc, al.audit_log_id desc
            limit 1
        ) invitation_audit on true
        returning admission_offer_id
    )
    select count(*)::int
    into v_migrated_count
    from inserted_offers;

    return v_migrated_count;
end;
$$ language plpgsql;

select migrate_legacy_event_attendee_invitations();

drop function migrate_legacy_event_attendee_invitations();

-- Preserve offer ownership, first-claim snapshots, and legal status transitions.
create or replace function check_admission_offer_lifecycle()
returns trigger as $$
begin
    -- Keep offer ownership and deadline identity immutable
    if row(
        new.created_at,
        new.event_id,
        new.event_ticket_type_id,
        new.expires_at,
        new.legacy,
        new.organizer_user_id,
        new.source,
        new.user_id
    ) is distinct from row(
        old.created_at,
        old.event_id,
        old.event_ticket_type_id,
        old.expires_at,
        old.legacy,
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

-- Prevent active offers from conflicting with enrollment state.
create or replace function check_admission_offer_enrollment_state()
returns trigger as $$
begin
    -- Ignore terminal offers that do not reserve capacity
    if new.status not in ('checkout_pending', 'pending') then
        return new;
    end if;

    -- Serialize writes for the same event-user enrollment boundary
    perform pg_advisory_xact_lock(hashtext(new.event_id::text), hashtext(new.user_id::text));

    -- Reject active attendee, queue, request, or purchase conflicts
    if exists (
        select 1
        from event_attendee ea
        where ea.event_id = new.event_id
        and ea.user_id = new.user_id
        and ea.status in ('confirmed', 'invitation-pending', 'registration-questions-pending')
    ) then
        raise exception 'user already has active attendance for this event';
    end if;

    if exists (
        select 1
        from event_waitlist ew
        where ew.event_id = new.event_id
        and ew.user_id = new.user_id
    ) then
        raise exception 'user is already on the waiting list for this event';
    end if;

    if exists (
        select 1
        from event_invitation_request eir
        where eir.event_id = new.event_id
        and eir.user_id = new.user_id
        and eir.status = 'pending'
    ) then
        raise exception 'user already has a pending invitation request for this event';
    end if;

    if exists (
        select 1
        from event_purchase ep
        where ep.event_id = new.event_id
        and ep.user_id = new.user_id
        and ep.status in (
            'completed',
            'pending',
            'refund-pending',
            'refund-recovery-pending',
            'refund-requested'
        )
        and ep.admission_offer_id is distinct from new.admission_offer_id
    ) then
        raise exception 'user already has an active purchase for this event';
    end if;

    return new;
end;
$$ language plpgsql;

-- Extend attendee writes with active-offer exclusivity.
create or replace function check_event_attendee_waitlist()
returns trigger as $$
begin
    -- Serialize writes for the same event-user pair across enrollment tables
    perform pg_advisory_xact_lock(hashtext(new.event_id::text), hashtext(new.user_id::text));

    if exists (
        select 1
        from event_waitlist ew
        where ew.event_id = new.event_id
        and ew.user_id = new.user_id
    ) then
        raise exception 'user is already on the waiting list for this event';
    end if;

    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = new.event_id
        and ao.user_id = new.user_id
        and ao.status in ('checkout_pending', 'pending')
        and not (
            new.status = 'registration-questions-pending'
            and ao.status = 'checkout_pending'
        )
    ) then
        raise exception 'user already has an active admission offer for this event';
    end if;

    return new;
end;
$$ language plpgsql;

-- Extend waitlist writes with active-offer exclusivity.
create or replace function check_event_waitlist_attendee()
returns trigger as $$
begin
    -- Serialize writes for the same event-user pair across enrollment tables
    perform pg_advisory_xact_lock(hashtext(new.event_id::text), hashtext(new.user_id::text));

    if exists (
        select 1
        from event_attendee ea
        where ea.event_id = new.event_id
        and ea.user_id = new.user_id
    ) then
        raise exception 'user is already attending this event';
    end if;

    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = new.event_id
        and ao.user_id = new.user_id
        and ao.status in ('checkout_pending', 'pending')
    ) then
        raise exception 'user already has an active admission offer for this event';
    end if;

    return new;
end;
$$ language plpgsql;

-- Prevent direct purchases from bypassing an active offer.
create or replace function check_event_purchase_admission_offer()
returns trigger as $$
begin
    -- Allow existing direct purchases to continue through financial recovery
    if tg_op = 'UPDATE'
       and new.status in ('refund-pending', 'refund-recovery-pending')
       and row(
            new.admission_offer_id,
            new.event_id,
            new.user_id
       ) is not distinct from row(
            old.admission_offer_id,
            old.event_id,
            old.user_id
       ) then
        return new;
    end if;

    -- Ignore historical purchases and purchases explicitly linked to an offer
    if new.admission_offer_id is not null
       or new.status not in (
            'completed',
            'pending',
            'refund-pending',
            'refund-recovery-pending',
            'refund-requested'
       ) then
        return new;
    end if;

    -- Serialize direct purchase creation with offer allocation
    perform pg_advisory_xact_lock(hashtext(new.event_id::text), hashtext(new.user_id::text));

    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = new.event_id
        and ao.user_id = new.user_id
        and ao.status in ('checkout_pending', 'pending')
    ) then
        raise exception 'active admission offer must be claimed directly';
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger event_attendee_waitlist_check on event_attendee;
drop trigger event_waitlist_attendee_check on event_waitlist;

create trigger admission_offer_enrollment_state_check
    before insert or update of event_id, status, user_id on admission_offer
    for each row
    execute function check_admission_offer_enrollment_state();

create trigger admission_offer_lifecycle_check
    before update on admission_offer
    for each row
    execute function check_admission_offer_lifecycle();

create trigger event_attendee_waitlist_check
    before insert or update of event_id, status, user_id on event_attendee
    for each row
    execute function check_event_attendee_waitlist();

create trigger event_purchase_admission_offer_check
    before insert or update of admission_offer_id, event_id, status, user_id on event_purchase
    for each row
    execute function check_event_purchase_admission_offer();

create trigger event_waitlist_attendee_check
    before insert or update of event_id, user_id on event_waitlist
    for each row
    execute function check_event_waitlist_attendee();

-- Register ticket-offer notification kinds.
insert into notification_kind (name)
values
    ('event-admission-offer-canceled'),
    ('event-admission-offer-created'),
    ('event-admission-offer-declined'),
    ('event-ticket-request-approved'),
    ('event-ticket-waitlist-offer');

-- Validate event-level ticketing consistency after normalized writes settle.
create or replace function check_event_ticketing_consistency()
returns trigger as $$
declare
    v_event_id uuid;
    v_event_ids uuid[];
    v_has_discount_codes boolean;
    v_has_positive_pricing boolean;
    v_payment_currency_code text;
begin
    -- Resolve every affected event, including both sides of row moves
    if tg_table_name in ('event', 'event_discount_code', 'event_ticket_type') then
        if tg_op = 'INSERT' then
            v_event_ids := array[new.event_id];
        elsif tg_op = 'DELETE' then
            v_event_ids := array[old.event_id];
        else
            v_event_ids := array[old.event_id, new.event_id];
        end if;
    elsif tg_table_name = 'event_ticket_price_window' then
        if tg_op = 'INSERT' then
            select array_agg(distinct ett.event_id) into v_event_ids
            from event_ticket_type ett
            where ett.event_ticket_type_id = new.event_ticket_type_id;
        elsif tg_op = 'DELETE' then
            select array_agg(distinct ett.event_id) into v_event_ids
            from event_ticket_type ett
            where ett.event_ticket_type_id = old.event_ticket_type_id;
        else
            select array_agg(distinct ett.event_id) into v_event_ids
            from event_ticket_type ett
            where ett.event_ticket_type_id = any(array[
                old.event_ticket_type_id,
                new.event_ticket_type_id
            ]);
        end if;
    else
        raise exception 'unsupported event ticketing consistency trigger table: %', tg_table_name;
    end if;

    -- Enforce the settled ticketing shape for each affected event
    foreach v_event_id in array coalesce(v_event_ids, array[]::uuid[])
    loop
        if v_event_id is null then
            continue;
        end if;

        select
            exists(
                select 1
                from event_discount_code edc
                where edc.event_id = e.event_id
            ),
            exists(
                select 1
                from event_ticket_type ett
                join event_ticket_price_window etpw using (event_ticket_type_id)
                where ett.event_id = e.event_id
                and etpw.amount_minor > 0
            ),
            e.payment_currency_code
        into
            v_has_discount_codes,
            v_has_positive_pricing,
            v_payment_currency_code
        from event e
        where e.event_id = v_event_id;

        if not found then
            continue;
        end if;

        if v_has_positive_pricing and v_payment_currency_code is null then
            raise exception 'positive ticket pricing requires payment_currency_code';
        end if;

        if not v_has_positive_pricing and v_has_discount_codes then
            raise exception 'discount_codes require positive ticket pricing';
        end if;

        if not v_has_positive_pricing and v_payment_currency_code is not null then
            raise exception 'payment_currency_code requires positive ticket pricing';
        end if;
    end loop;

    return null;
end;
$$ language plpgsql;

create constraint trigger event_ticketing_consistency_on_event_ticket_price_window
    after insert or update or delete on event_ticket_price_window
    deferrable initially deferred
    for each row
    execute function check_event_ticketing_consistency();

-- Remove superseded operation signatures before loading provider-aware functions.
drop function if exists add_event(uuid, uuid, jsonb, jsonb);
drop function if exists add_event_series(uuid, uuid, jsonb, jsonb, jsonb);
drop function if exists cancel_event_admission_offer(uuid, uuid, uuid, text);
drop function if exists decline_event_admission_offer(uuid, uuid, text);
drop function if exists prepare_event_checkout_validate_event(uuid, uuid, text);
drop function if exists reconcile_next_event_enrollment(text);
drop function if exists release_event_admission_offer(uuid, text, uuid, uuid, text);
drop function if exists update_event(uuid, uuid, uuid, jsonb, jsonb);
drop function if exists validate_event_enrollment_payload(boolean, jsonb, boolean);
drop function if exists validate_event_ticketing_payload(jsonb, text, jsonb, boolean);
