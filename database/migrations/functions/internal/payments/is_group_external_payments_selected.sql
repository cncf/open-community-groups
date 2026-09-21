-- Returns whether a group has selected the external payment rail: it opted in
-- and its country is allowlisted. Selection decides which rail paid events use;
-- is_group_external_payments_ready decides whether that rail can collect.
create or replace function is_group_external_payments_selected(
    p_group_id uuid
)
returns boolean as $$
    select exists (
        select 1
        from "group" g
        where g.group_id = p_group_id
        and g.external_payments_enabled
        and is_country_external_payments_allowlisted(g.country_code)
    );
$$ language sql;
