-- Returns whether a group can currently collect new external payments: the
-- external rail is selected and the legal name of the collecting organization
-- is stored.
create or replace function is_group_external_payments_ready(
    p_group_id uuid
)
returns boolean as $$
    select exists (
        select 1
        from "group" g
        where g.group_id = p_group_id
        and g.external_payments_seller_display_name is not null
        and is_group_external_payments_selected(g.group_id)
    );
$$ language sql;
