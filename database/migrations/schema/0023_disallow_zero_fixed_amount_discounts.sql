-- Disallow zero-value fixed amount discount codes.

alter table event_discount_code
    drop constraint if exists event_discount_code_amount_minor_check;

alter table event_discount_code
    add constraint event_discount_code_amount_minor_check
        check (amount_minor is null or amount_minor > 0);
