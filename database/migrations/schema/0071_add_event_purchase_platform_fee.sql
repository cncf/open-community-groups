-- Adds a snapshotted platform fee amount to event purchases.

alter table event_purchase
    add column platform_fee_amount_minor bigint default 0 not null
    constraint event_purchase_platform_fee_amount_minor_chk check (
        platform_fee_amount_minor >= 0
        and platform_fee_amount_minor <= amount_minor
    );

drop function if exists prepare_event_checkout_purchase(uuid, uuid, uuid, uuid, text, text, jsonb, uuid);
