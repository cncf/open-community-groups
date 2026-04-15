-- Add payments, ticketing, purchases, and refund requests.

-- Register supported payment providers
create table payment_provider (
    payment_provider_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

insert into payment_provider (payment_provider_id, display_name)
values ('stripe', 'Stripe');

-- Extend groups and events with payout recipient and ticketing currency
alter table "group"
    add column payment_recipient jsonb;

alter table event
    add column payment_currency_code text
    check (btrim(payment_currency_code) <> '');

-- Store event-level discount codes
create table event_discount_code (
    event_discount_code_id uuid primary key,
    active boolean default true not null,
    code text not null check (btrim(code) <> ''),
    created_at timestamptz default current_timestamp not null,
    event_id uuid not null references event on delete cascade,
    kind text not null check (
        kind = any(array['fixed_amount', 'percentage']::text[])
    ),
    title text not null check (btrim(title) <> ''),
    updated_at timestamptz default current_timestamp not null,

    available int check (available is null or available >= 0),
    amount_minor bigint check (amount_minor is null or amount_minor >= 0),
    ends_at timestamptz,
    percentage int check (percentage is null or (percentage >= 1 and percentage <= 100)),
    starts_at timestamptz,
    total_available int check (total_available is null or total_available >= 0),

    constraint event_discount_code_event_id_event_discount_code_id_key
        unique (event_id, event_discount_code_id),
    constraint event_discount_code_kind_value_chk check (
        (kind = 'fixed_amount' and amount_minor is not null and percentage is null)
        or (kind = 'percentage' and percentage is not null and amount_minor is null)
    ),
    constraint event_discount_code_window_chk check (
        ends_at is null or starts_at is null or ends_at >= starts_at
    )
);

create index event_discount_code_event_id_idx on event_discount_code (event_id);
create unique index event_discount_code_event_id_upper_code_idx
    on event_discount_code (event_id, upper(code));

-- Store event ticket tiers
create table event_ticket_type (
    event_ticket_type_id uuid primary key,
    active boolean default true not null,
    created_at timestamptz default current_timestamp not null,
    event_id uuid not null references event on delete cascade,
    "order" int not null,
    seats_total int not null check (seats_total >= 0),
    title text not null check (btrim(title) <> ''),
    updated_at timestamptz default current_timestamp not null,

    description text check (btrim(description) <> ''),

    constraint event_ticket_type_event_id_event_ticket_type_id_key
        unique (event_id, event_ticket_type_id)
);

create index event_ticket_type_event_id_idx on event_ticket_type (event_id);

-- Store date-based price windows for each ticket tier
create table event_ticket_price_window (
    event_ticket_price_window_id uuid primary key,
    amount_minor bigint not null check (amount_minor >= 0),
    created_at timestamptz default current_timestamp not null,
    event_ticket_type_id uuid not null references event_ticket_type on delete cascade,
    updated_at timestamptz default current_timestamp not null,

    ends_at timestamptz,
    starts_at timestamptz,

    constraint event_ticket_price_window_window_chk check (
        ends_at is null or starts_at is null or ends_at >= starts_at
    )
);

create index event_ticket_price_window_event_ticket_type_id_idx
    on event_ticket_price_window (event_ticket_type_id);

-- Store event checkout holds, completed purchases, and provider references
create table event_purchase (
    event_purchase_id uuid primary key default gen_random_uuid(),
    amount_minor bigint not null check (amount_minor >= 0),
    created_at timestamptz default current_timestamp not null,
    currency_code text not null check (btrim(currency_code) <> ''),
    discount_amount_minor bigint default 0 not null check (discount_amount_minor >= 0),
    event_id uuid not null references event,
    event_ticket_type_id uuid not null references event_ticket_type,
    status text not null check (
        status = any(array[
            'completed',
            'expired',
            'pending',
            'refund-pending',
            'refund-requested',
            'refunded'
        ]::text[])
    ),
    ticket_title text not null check (btrim(ticket_title) <> ''),
    updated_at timestamptz default current_timestamp not null,
    user_id uuid not null references "user",

    completed_at timestamptz,
    discount_code text check (btrim(discount_code) <> ''),
    event_discount_code_id uuid references event_discount_code,
    hold_expires_at timestamptz,
    payment_provider_id text references payment_provider,
    provider_checkout_session_id text check (btrim(provider_checkout_session_id) <> ''),
    provider_checkout_url text check (btrim(provider_checkout_url) <> ''),
    provider_payment_reference text check (btrim(provider_payment_reference) <> ''),
    refunded_at timestamptz,

    constraint event_purchase_event_discount_code_belongs_to_event_fkey
        foreign key (event_id, event_discount_code_id)
            references event_discount_code (event_id, event_discount_code_id),
    constraint event_purchase_event_ticket_type_belongs_to_event_fkey
        foreign key (event_id, event_ticket_type_id)
            references event_ticket_type (event_id, event_ticket_type_id)
);

-- Support attendee purchase lookups and provider webhook reconciliation
create index event_purchase_event_id_idx on event_purchase (event_id);
create index event_purchase_event_id_status_idx on event_purchase (event_id, status);
create index event_purchase_user_id_idx on event_purchase (user_id);
create unique index event_purchase_provider_checkout_session_idx
    on event_purchase (payment_provider_id, provider_checkout_session_id)
    where provider_checkout_session_id is not null;
create unique index event_purchase_event_id_user_id_active_idx
    on event_purchase (event_id, user_id)
    where status = any(array['completed', 'pending', 'refund-requested']::text[]);

-- Track attendee-initiated refund requests and organizer review outcomes
create table event_refund_request (
    event_refund_request_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    event_purchase_id uuid not null unique references event_purchase,
    requested_by_user_id uuid not null references "user",
    status text not null check (
        status = any(array['approved', 'approving', 'pending', 'rejected']::text[])
    ),
    updated_at timestamptz default current_timestamp not null,

    requested_reason text check (btrim(requested_reason) <> ''),
    review_note text check (btrim(review_note) <> ''),
    reviewed_at timestamptz,
    reviewed_by_user_id uuid references "user"
);

create index event_refund_request_status_idx on event_refund_request (status);

-- Validate event-level ticketing consistency after normalized writes settle
create or replace function check_event_ticketing_consistency()
returns trigger as $$
declare
    v_event_id uuid;
    v_has_discount_codes boolean;
    v_has_ticket_types boolean;
    v_payment_currency_code text;
begin
    -- Resolve the affected event regardless of which table fired the trigger
    if tg_table_name = 'event' then
        v_event_id := coalesce(new.event_id, old.event_id);
    elsif tg_table_name = 'event_discount_code' then
        v_event_id := coalesce(new.event_id, old.event_id);
    elsif tg_table_name = 'event_ticket_type' then
        v_event_id := coalesce(new.event_id, old.event_id);
    else
        raise exception 'unsupported event ticketing consistency trigger table: %', tg_table_name;
    end if;

    if v_event_id is null then
        return null;
    end if;

    -- Skip rows whose parent event no longer exists
    select
        exists(
            select 1
            from event_discount_code
            where event_id = e.event_id
        ),
        exists(
            select 1
            from event_ticket_type
            where event_id = e.event_id
        ),
        e.payment_currency_code
    into
        v_has_discount_codes,
        v_has_ticket_types,
        v_payment_currency_code
    from event e
    where e.event_id = v_event_id;

    if not found then
        return null;
    end if;

    -- Enforce the persisted ticketing shape for each event
    if v_has_ticket_types and v_payment_currency_code is null then
        raise exception 'ticketed events require payment_currency_code';
    end if;

    if not v_has_ticket_types and v_has_discount_codes then
        raise exception 'discount_codes require ticket_types';
    end if;

    if not v_has_ticket_types and v_payment_currency_code is not null then
        raise exception 'payment_currency_code requires ticket_types';
    end if;

    return null;
end;
$$ language plpgsql;

create constraint trigger event_ticketing_consistency_on_event
    after insert or update of payment_currency_code on event
    deferrable initially deferred
    for each row
    execute function check_event_ticketing_consistency();

create constraint trigger event_ticketing_consistency_on_event_discount_code
    after insert or update or delete on event_discount_code
    deferrable initially deferred
    for each row
    execute function check_event_ticketing_consistency();

create constraint trigger event_ticketing_consistency_on_event_ticket_type
    after insert or update or delete on event_ticket_type
    deferrable initially deferred
    for each row
    execute function check_event_ticketing_consistency();

-- Drop the main-branch publish_event signature before loading the provider-aware one
drop function if exists publish_event(uuid, uuid, uuid);

-- Register notification kinds used by refund-request and refund-review flows
insert into notification_kind (name) values ('event-refund-approved');
insert into notification_kind (name) values ('event-refund-rejected');
insert into notification_kind (name) values ('event-refund-requested');
