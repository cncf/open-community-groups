-- Persist explicit discount-code availability override state.

alter table event_discount_code
    add column available_override_active boolean default false not null;

-- Normalize legacy rows conservatively by preserving any stored manual count.
update event_discount_code
set available_override_active = true
where available is not null;
