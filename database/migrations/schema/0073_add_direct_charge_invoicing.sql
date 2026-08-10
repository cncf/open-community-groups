-- Adds seller-scoped direct-charge invoicing, tax, and adjustments.

-- Record event tax choices used by future paid purchases.
alter table event
    add column tax_behavior text default 'inclusive' not null,
    add column tax_calculation_mode text default 'automatic' not null,
    add constraint event_tax_behavior_chk check (
        tax_behavior = any(array['exclusive', 'inclusive']::text[])
    ),
    add constraint event_tax_calculation_mode_chk check (
        tax_calculation_mode = any(array['automatic', 'manual']::text[])
    );

-- Preserve the provisional fee while adding authoritative purchase amounts.
alter table event_purchase
    rename column platform_fee_amount_minor to provisional_platform_fee_amount_minor;

-- Paid purchases never shipped, so refuse ambiguous historical financial rows
-- before adding the direct-charge-only constraints.
do $$
begin
    if exists (select 1 from event_purchase where amount_minor > 0) then
        raise exception 'paid purchases must be removed before direct-charge migration';
    end if;
end;
$$;

alter table event_purchase
    drop constraint event_purchase_platform_fee_amount_minor_chk,
    add column charge_model text default 'ocg-free' not null,
    add column platform_fee_bps int default 0 not null check (
        platform_fee_bps >= 0 and platform_fee_bps < 10000
    ),

    add column connected_seller_id text check (btrim(connected_seller_id) <> ''),
    add column final_platform_fee_amount_minor bigint,
    add column financially_reconciled_at timestamptz,
    add column manual_tax_snapshot jsonb,
    add column performance_location_fingerprint text check (
        btrim(performance_location_fingerprint) <> ''
    ),
    add column provider_application_fee_id text check (
        btrim(provider_application_fee_id) <> ''
    ),
    add column provider_charge_id text check (btrim(provider_charge_id) <> ''),
    add column provider_invoice_hosted_url text check (
        btrim(provider_invoice_hosted_url) <> ''
    ),
    add column provider_invoice_id text check (btrim(provider_invoice_id) <> ''),
    add column provider_invoice_pdf_url text check (
        btrim(provider_invoice_pdf_url) <> ''
    ),
    add column provider_object_account_id text check (
        btrim(provider_object_account_id) <> ''
    ),
    add column provider_product_fingerprint text check (
        btrim(provider_product_fingerprint) <> ''
    ),
    add column provider_tax_code text check (btrim(provider_tax_code) <> ''),
    add column provider_tax_location_id text check (
        btrim(provider_tax_location_id) <> ''
    ),
    add column provider_tax_product_id text check (
        btrim(provider_tax_product_id) <> ''
    ),
    add column provider_total_minor bigint,
    add column seller_snapshot jsonb,
    add column subtotal_excluding_tax_minor bigint,
    add column tax_amount_minor bigint,
    add column tax_behavior text,
    add column tax_calculation_mode text,
    add column tax_classification text,
    add column venue_snapshot jsonb,

    add constraint event_purchase_charge_model_chk check (
        (charge_model = 'direct-charge' and amount_minor > 0)
        or (charge_model = 'ocg-free' and amount_minor = 0)
    ),
    add constraint event_purchase_direct_charge_context_chk check (
        charge_model <> 'direct-charge'
        or (
            connected_seller_id is not null
            and currency_code is not null
            and provider_object_account_id = connected_seller_id
            and seller_snapshot is not null
            and tax_behavior is not null
            and tax_calculation_mode is not null
            and tax_classification = 'professional-event-admission'
            and venue_snapshot is not null
        )
    ),
    add constraint event_purchase_financial_amounts_chk check (
        (
            final_platform_fee_amount_minor is null
            and provider_total_minor is null
            and subtotal_excluding_tax_minor is null
            and tax_amount_minor is null
        )
        or (
            final_platform_fee_amount_minor is not null
            and provider_total_minor is not null
            and subtotal_excluding_tax_minor is not null
            and tax_amount_minor is not null
            and final_platform_fee_amount_minor >= 0
            and final_platform_fee_amount_minor
                <= provisional_platform_fee_amount_minor
            and final_platform_fee_amount_minor <= subtotal_excluding_tax_minor
            and provider_total_minor = subtotal_excluding_tax_minor + tax_amount_minor
            and provider_total_minor >= 0
            and subtotal_excluding_tax_minor >= 0
            and tax_amount_minor >= 0
        )
    ),
    add constraint event_purchase_provider_product_mode_chk check (
        tax_calculation_mode <> 'automatic'
        or charge_model <> 'direct-charge'
        or provider_checkout_session_id is null
        or (
            provider_tax_code is not null
            and provider_tax_code = 'txcd_50013001'
            and provider_tax_location_id is not null
            and provider_tax_product_id is not null
        )
    ),
    add constraint event_purchase_provisional_platform_fee_amount_minor_chk check (
        provisional_platform_fee_amount_minor >= 0
        and provisional_platform_fee_amount_minor <= amount_minor
    ),
    add constraint event_purchase_tax_behavior_chk check (
        tax_behavior is null
        or tax_behavior = any(array['exclusive', 'inclusive']::text[])
    ),
    add constraint event_purchase_tax_calculation_mode_chk check (
        tax_calculation_mode is null
        or tax_calculation_mode = any(array['automatic', 'manual']::text[])
    );

alter table event_purchase
    add constraint event_purchase_completed_direct_charge_amounts_chk check (
        charge_model <> 'direct-charge'
        or status not in (
            'completed',
            'refund-pending',
            'refund-recovery-pending',
            'refund-requested',
            'refunded'
        )
        or (
            final_platform_fee_amount_minor is not null
            and payment_provider_id is not null
            and provider_charge_id is not null
            and provider_checkout_session_id is not null
            and provider_payment_reference is not null
            and provider_total_minor is not null
            and subtotal_excluding_tax_minor is not null
            and tax_amount_minor is not null
        )
    );

-- Scope all connected-account provider references by their owning account.
drop index event_purchase_provider_checkout_session_idx;

create unique index event_purchase_provider_charge_id_idx
    on event_purchase (
        payment_provider_id,
        provider_object_account_id,
        provider_charge_id
    )
    where provider_charge_id is not null;
create unique index event_purchase_provider_checkout_session_idx
    on event_purchase (
        payment_provider_id,
        provider_object_account_id,
        provider_checkout_session_id
    )
    where provider_checkout_session_id is not null;
create unique index event_purchase_provider_invoice_id_idx
    on event_purchase (
        payment_provider_id,
        provider_object_account_id,
        provider_invoice_id
    )
    where provider_invoice_id is not null;
create unique index event_purchase_provider_payment_reference_idx
    on event_purchase (
        payment_provider_id,
        provider_object_account_id,
        provider_payment_reference
    )
    where provider_payment_reference is not null;

-- Store immutable sponsor-approved manual venue tax configurations.
create table event_manual_tax_configuration (
    event_manual_tax_configuration_id uuid primary key default gen_random_uuid(),
    approved_at timestamptz not null,
    approved_by_user_id uuid not null references "user",
    connected_seller_id text not null check (btrim(connected_seller_id) <> ''),
    created_at timestamptz default current_timestamp not null,
    currency_code text not null check (btrim(currency_code) <> ''),
    event_id uuid not null references event,
    evidence_reference text not null check (btrim(evidence_reference) <> ''),
    tax_behavior text not null,
    valid_from timestamptz default current_timestamp not null,
    venue_snapshot jsonb not null,
    version int not null check (version > 0),

    valid_until timestamptz,

    constraint event_manual_tax_configuration_event_version_key
        unique (event_id, version),
    constraint event_manual_tax_configuration_id_behavior_key
        unique (event_manual_tax_configuration_id, tax_behavior),
    constraint event_manual_tax_configuration_tax_behavior_chk check (
        tax_behavior = any(array['exclusive', 'inclusive']::text[])
    ),
    constraint event_manual_tax_configuration_validity_chk check (
        valid_until is null or valid_until > valid_from
    ),
    constraint event_manual_tax_configuration_venue_chk check (
        nullif(btrim(venue_snapshot->>'address'), '') is not null
        and nullif(btrim(venue_snapshot->>'city'), '') is not null
        and nullif(btrim(venue_snapshot->>'country_code'), '') is not null
        and nullif(btrim(venue_snapshot->>'name'), '') is not null
        and nullif(btrim(venue_snapshot->>'zip_code'), '') is not null
    )
);

-- Store the jurisdictional rates that compose a manual tax configuration.
create table event_manual_tax_component (
    event_manual_tax_component_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    display_name text not null check (btrim(display_name) <> ''),
    event_manual_tax_configuration_id uuid not null,
    jurisdiction text not null check (btrim(jurisdiction) <> ''),
    percentage numeric(8, 4) not null check (percentage > 0 and percentage <= 100),
    provider_tax_rate_id text not null check (btrim(provider_tax_rate_id) <> ''),
    tax_behavior text not null,
    tax_type text not null check (btrim(tax_type) <> ''),

    country_code text check (btrim(country_code) <> ''),
    state text check (btrim(state) <> ''),

    constraint event_manual_tax_component_configuration_behavior_fkey
        foreign key (event_manual_tax_configuration_id, tax_behavior)
            references event_manual_tax_configuration (
                event_manual_tax_configuration_id,
                tax_behavior
            )
);

create index event_manual_tax_component_configuration_id_idx
    on event_manual_tax_component (event_manual_tax_configuration_id);
create unique index event_manual_tax_configuration_event_id_active_idx
    on event_manual_tax_configuration (event_id)
    where valid_until is null;
create index event_manual_tax_configuration_event_id_idx
    on event_manual_tax_configuration (event_id, valid_from, valid_until);

-- Prevent more than one manual-tax version from applying at any instant.
create function check_event_manual_tax_configuration_validity()
returns trigger as $$
declare
    v_event_id uuid;
    v_valid_from timestamptz;
    v_valid_until timestamptz;
begin
    -- Reload the settled row because this constraint trigger is deferred
    select
        emtc.event_id,
        emtc.valid_from,
        emtc.valid_until
    into
        v_event_id,
        v_valid_from,
        v_valid_until
    from event_manual_tax_configuration emtc
    where emtc.event_manual_tax_configuration_id =
        new.event_manual_tax_configuration_id;

    if not found then
        return null;
    end if;

    -- Serialize validity checks so concurrent bounded versions cannot overlap
    perform pg_advisory_xact_lock(
        hashtext('event-manual-tax-configuration'),
        hashtext(v_event_id::text)
    );

    if exists (
        select 1
        from event_manual_tax_configuration emtc
        where emtc.event_id = v_event_id
        and emtc.event_manual_tax_configuration_id <>
            new.event_manual_tax_configuration_id
        and tstzrange(emtc.valid_from, emtc.valid_until, '[)')
            && tstzrange(v_valid_from, v_valid_until, '[)')
    ) then
        raise exception 'manual tax configuration validity periods cannot overlap for one event';
    end if;

    return null;
end;
$$ language plpgsql;

create constraint trigger event_manual_tax_configuration_validity_check
    after insert or update on event_manual_tax_configuration
    deferrable initially deferred
    for each row
    execute function check_event_manual_tax_configuration_validity();

-- Cache immutable provider resources by seller account and complete fingerprint.
create table payment_provider_tax_location (
    payment_provider_tax_location_id uuid primary key default gen_random_uuid(),
    connected_seller_id text not null check (btrim(connected_seller_id) <> ''),
    created_at timestamptz default current_timestamp not null,
    fingerprint text not null check (btrim(fingerprint) <> ''),
    payment_provider_id text not null references payment_provider,
    provider_tax_location_id text not null check (
        btrim(provider_tax_location_id) <> ''
    ),
    venue_snapshot jsonb not null,

    constraint payment_provider_tax_location_seller_fingerprint_key
        unique (payment_provider_id, connected_seller_id, fingerprint),
    constraint payment_provider_tax_location_seller_provider_id_key
        unique (
            payment_provider_id,
            connected_seller_id,
            provider_tax_location_id
        )
);

-- Cache immutable provider tax products by seller account and fingerprint.
create table payment_provider_tax_product (
    payment_provider_tax_product_id uuid primary key default gen_random_uuid(),
    connected_seller_id text not null check (btrim(connected_seller_id) <> ''),
    created_at timestamptz default current_timestamp not null,
    fingerprint text not null check (btrim(fingerprint) <> ''),
    payment_provider_id text not null references payment_provider,
    provider_tax_location_id text not null check (
        btrim(provider_tax_location_id) <> ''
    ),
    provider_tax_product_id text not null check (
        btrim(provider_tax_product_id) <> ''
    ),
    tax_code text not null check (btrim(tax_code) <> ''),
    title text not null check (btrim(title) <> ''),

    constraint payment_provider_tax_product_seller_fingerprint_key
        unique (payment_provider_id, connected_seller_id, fingerprint),
    constraint payment_provider_tax_product_seller_provider_id_key
        unique (
            payment_provider_id,
            connected_seller_id,
            provider_tax_product_id
        )
);

-- Persist application-fee refunds before provider calls.
create table event_purchase_application_fee_adjustment (
    event_purchase_application_fee_adjustment_id uuid primary key default gen_random_uuid(),
    amount_minor bigint not null check (amount_minor > 0),
    attempt_count int default 0 not null check (attempt_count >= 0),
    created_at timestamptz default current_timestamp not null,
    event_purchase_id uuid not null references event_purchase,
    idempotency_key text not null check (btrim(idempotency_key) <> ''),
    kind text not null,
    next_attempt_at timestamptz default current_timestamp not null,
    status text default 'pending' not null,
    updated_at timestamptz default current_timestamp not null,

    claim_id uuid,
    claimed_at timestamptz,
    completed_at timestamptz,
    failure_message text check (btrim(failure_message) <> ''),
    provider_application_fee_refund_id text check (
        btrim(provider_application_fee_refund_id) <> ''
    ),
    recovery_completed_at timestamptz,
    recovery_completed_by_user_id uuid references "user",
    recovery_note text check (btrim(recovery_note) <> ''),
    recovery_reference text check (btrim(recovery_reference) <> ''),

    constraint event_purchase_application_fee_adjustment_claim_chk check (
        (status = 'processing' and claim_id is not null and claimed_at is not null)
        or (status <> 'processing' and claim_id is null and claimed_at is null)
    ),
    constraint event_purchase_application_fee_adjustment_kind_chk check (
        kind = any(array[
            'purchase-refund',
            'tax-reconciliation'
        ]::text[])
    ),
    constraint event_purchase_application_fee_adjustment_purchase_kind_key
        unique (event_purchase_id, kind),
    constraint event_purchase_application_fee_adjustment_recovery_chk check (
        (
            recovery_completed_at is null
            and recovery_completed_by_user_id is null
            and recovery_note is null
            and recovery_reference is null
        )
        or (
            recovery_completed_at is not null
            and recovery_completed_by_user_id is not null
            and recovery_note is not null
            and recovery_reference is not null
            and completed_at is not null
            and provider_application_fee_refund_id is not null
            and status = 'completed'
        )
    ),
    constraint event_purchase_application_fee_adjustment_status_chk check (
        status = any(array[
            'completed',
            'failed',
            'pending',
            'processing'
        ]::text[])
    ),
    constraint event_purchase_application_fee_adjustment_terminal_chk check (
        (
            status = 'completed'
            and completed_at is not null
            and provider_application_fee_refund_id is not null
        )
        or (
            status <> 'completed'
            and completed_at is null
            and provider_application_fee_refund_id is null
        )
    )
);

create unique index event_purchase_application_fee_adjustment_idempotency_key_idx
    on event_purchase_application_fee_adjustment (idempotency_key);
create unique index event_purchase_application_fee_adjustment_provider_refund_idx
    on event_purchase_application_fee_adjustment (
        provider_application_fee_refund_id
    )
    where provider_application_fee_refund_id is not null;
create index event_purchase_application_fee_adjustment_work_idx
    on event_purchase_application_fee_adjustment (status, next_attempt_at);

-- Persist linked credit-note creation independently from customer refunds.
create table event_purchase_credit_note (
    event_purchase_credit_note_id uuid primary key default gen_random_uuid(),
    amount_minor bigint not null check (amount_minor > 0),
    attempt_count int default 0 not null check (attempt_count >= 0),
    created_at timestamptz default current_timestamp not null,
    currency_code text not null check (btrim(currency_code) <> ''),
    event_purchase_refund_id uuid not null unique references event_purchase_refund,
    idempotency_key text not null unique check (btrim(idempotency_key) <> ''),
    next_attempt_at timestamptz default current_timestamp not null,
    payment_provider_id text not null references payment_provider,
    provider_object_account_id text not null check (
        btrim(provider_object_account_id) <> ''
    ),
    status text default 'pending' not null,
    tax_amount_minor bigint not null check (tax_amount_minor >= 0),
    updated_at timestamptz default current_timestamp not null,

    claim_id uuid,
    claimed_at timestamptz,
    completed_at timestamptz,
    failure_message text check (btrim(failure_message) <> ''),
    provider_credit_note_id text check (btrim(provider_credit_note_id) <> ''),
    provider_hosted_url text check (btrim(provider_hosted_url) <> ''),
    provider_pdf_url text check (btrim(provider_pdf_url) <> ''),
    recovery_completed_at timestamptz,
    recovery_completed_by_user_id uuid references "user",
    recovery_note text check (btrim(recovery_note) <> ''),
    recovery_reference text check (btrim(recovery_reference) <> ''),

    constraint event_purchase_credit_note_claim_chk check (
        (status = 'processing' and claim_id is not null and claimed_at is not null)
        or (status <> 'processing' and claim_id is null and claimed_at is null)
    ),
    constraint event_purchase_credit_note_recovery_chk check (
        (
            recovery_completed_at is null
            and recovery_completed_by_user_id is null
            and recovery_note is null
            and recovery_reference is null
        )
        or (
            recovery_completed_at is not null
            and recovery_completed_by_user_id is not null
            and recovery_note is not null
            and recovery_reference is not null
            and completed_at is not null
            and provider_credit_note_id is not null
            and status = 'issued'
        )
    ),
    constraint event_purchase_credit_note_status_chk check (
        status = any(array['failed', 'issued', 'pending', 'processing']::text[])
    ),
    constraint event_purchase_credit_note_terminal_chk check (
        (
            status = 'issued'
            and completed_at is not null
            and provider_credit_note_id is not null
        )
        or (
            status <> 'issued'
            and completed_at is null
            and provider_credit_note_id is null
        )
    )
);

create unique index event_purchase_credit_note_provider_id_idx
    on event_purchase_credit_note (
        payment_provider_id,
        provider_object_account_id,
        provider_credit_note_id
    )
    where provider_credit_note_id is not null;
create index event_purchase_credit_note_work_idx
    on event_purchase_credit_note (status, next_attempt_at);

-- Replace function signatures whose persisted contract changes in this release.
drop function if exists attach_checkout_session_to_event_purchase(uuid, text, text, text);
drop function if exists expire_event_purchase_for_checkout_session(text, text);
drop function if exists prepare_event_checkout_purchase(uuid, uuid, uuid, uuid, text, text, jsonb, uuid, int);
drop function if exists publish_event_series_events(uuid, uuid, uuid[], text);
drop function if exists publish_event(uuid, uuid, uuid, text);
drop function if exists reconcile_event_purchase_for_checkout_session(text, text, text);
drop function if exists validate_event_ticketing_payment_readiness(text, boolean, text, jsonb);
drop function if exists validate_event_ticketing_payload(text, jsonb, text, jsonb, jsonb, boolean);
