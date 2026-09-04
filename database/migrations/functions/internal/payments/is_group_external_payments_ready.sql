-- Returns whether a group can currently collect new external payments.
create or replace function is_group_external_payments_ready(
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
