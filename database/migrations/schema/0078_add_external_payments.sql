-- Adds external payments configuration, group opt-in, event fields, and purchase snapshots.

-- Persist the operator allowlist and window limits as a single-row table.
create table external_payments_config (
    singleton boolean primary key default true check (singleton),
    allowed_countries text[] not null,
    default_payment_window_hours int not null,
    max_payment_window_hours int not null,
    updated_at timestamptz default current_timestamp not null,

    constraint external_payments_config_allowed_countries_chk check (
        cardinality(allowed_countries) > 0
    ),
    constraint external_payments_config_window_hours_chk check (
        default_payment_window_hours >= 1
        and max_payment_window_hours >= default_payment_window_hours
        and max_payment_window_hours <= 8760
    )
);

-- Add the group-level opt-in toggle and per-event external payment fields.
alter table "group"
    add column external_payments_enabled boolean not null default false;

alter table event
    add column external_payment_instructions text
        check (btrim(external_payment_instructions) <> ''),
    add column external_payment_url text
        check (btrim(external_payment_url) <> ''),
    add column external_payment_window_hours int
        check (external_payment_window_hours between 1 and 8760);

-- Record per-purchase external confirmation state and extend the charge-model contract.
alter table event_purchase
    drop constraint event_purchase_charge_model_chk,
    add column external_payment_details text
        check (btrim(external_payment_details) <> ''),
    add column external_payment_marked_by_user_id uuid references "user",
    add column external_payment_reminder_sent_at timestamptz,
    add constraint event_purchase_charge_model_chk check (
        (charge_model = 'direct-charge' and amount_minor > 0)
        or (charge_model = 'external' and amount_minor > 0)
        or (charge_model = 'ocg-free' and amount_minor = 0)
    ),
    add constraint event_purchase_external_chk check (
        (
            charge_model = 'external'
            and connected_seller_id is null
            and payment_provider_id is null
            and platform_fee_bps = 0
            and provider_object_account_id is null
            and provisional_platform_fee_amount_minor = 0
            and seller_snapshot is null
            and tax_behavior is null
            and tax_calculation_mode is null
            and tax_classification is null
            and venue_snapshot is null
        )
        or (
            charge_model <> 'external'
            and external_payment_details is null
            and external_payment_marked_by_user_id is null
            and external_payment_reminder_sent_at is null
        )
    );

-- Keep the live event payment URL while pending external holds still need it.
create or replace function check_event_external_payment_url()
returns trigger as $$
begin
    -- Allow assignment, replacement, and no-op URL updates
    if new.external_payment_url is not null
       or old.external_payment_url is null then
        return new;
    end if;

    -- Reject clearing the URL while an external hold can still be resumed
    if exists (
        select 1
        from event_purchase ep
        where ep.event_id = old.event_id
        and ep.charge_model = 'external'
        and ep.status = 'pending'
    ) then
        raise exception 'external payment url cannot be cleared while pending external purchases exist';
    end if;

    return new;
end;
$$ language plpgsql;

create trigger event_external_payment_url_check
before update of external_payment_url on event
for each row execute function check_event_external_payment_url();

-- Add transactional external-payment notification kinds.
insert into notification_kind (name, optional_notification)
values
    ('event-external-payment-expired', false),
    ('event-external-payment-pending', false),
    ('event-external-payment-reminder', false);

-- Replace the payment-readiness signature that now accepts external-mode fields.
drop function if exists validate_event_ticketing_payment_readiness(text, boolean, text, jsonb, uuid, jsonb);

-- Allow claiming a pending offer into a longer external checkout deadline.
create or replace function check_admission_offer_lifecycle()
returns trigger as $$
begin
    -- Keep offer ownership identity immutable
    if row(
        new.created_at,
        new.event_id,
        new.event_ticket_type_id,
        new.organizer_user_id,
        new.source,
        new.user_id
    ) is distinct from row(
        old.created_at,
        old.event_id,
        old.event_ticket_type_id,
        old.organizer_user_id,
        old.source,
        old.user_id
    ) then
        raise exception 'admission offer ownership and deadline fields are immutable';
    end if;

    -- Preserve the stored deadline except when moving into a longer hold
    if new.expires_at is distinct from old.expires_at
       and not (
            old.status in ('checkout_pending', 'pending')
            and new.status = 'checkout_pending'
            and new.expires_at >= old.expires_at
       ) then
        raise exception 'admission offer ownership and deadline fields are immutable';
    end if;

    -- Preserve a stored price snapshot except when a pending offer is claimed
    if old.amount_minor is not null
       and not (
            old.status = 'pending'
            and new.status = 'checkout_pending'
       )
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
