-- Resolves whether a discount code payload keeps Uses remaining in manual
-- override mode: an explicit clear wins, then an explicit override flag, then
-- a submitted count enables the override, otherwise the prior state is kept
-- (false for new codes). Shared by sync_event_discount_codes and the
-- configuration comparison so the persisted rule cannot drift.
create or replace function resolve_event_discount_code_available_override(
    p_discount_code jsonb,
    p_previous_override_active boolean default false
)
returns boolean as $$
    select case
        -- Clearing Uses remaining disables the override
        when coalesce((p_discount_code->>'available_cleared')::boolean, false) then false
        -- Honor an explicit override flag
        when (p_discount_code->>'available_override_active') is not null
            then (p_discount_code->>'available_override_active')::boolean
        -- A submitted count enables the override
        when (p_discount_code->>'available') is not null then true
        -- Keep the prior override state
        else p_previous_override_active
    end;
$$ language sql immutable;
