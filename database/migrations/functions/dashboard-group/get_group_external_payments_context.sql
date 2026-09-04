-- Returns group-level external-payments eligibility and window limits.
create or replace function get_group_external_payments_context(
    p_community_id uuid,
    p_group_id uuid
)
returns jsonb as $$
    select jsonb_strip_nulls(jsonb_build_object(
        'configured', cfg.singleton is not null,
        'eligible', is_country_external_payments_allowlisted(g.country_code),
        'enabled', g.external_payments_enabled,

        'country_code', g.country_code,
        'default_payment_window_hours', cfg.default_payment_window_hours,
        'max_payment_window_hours', cfg.max_payment_window_hours
    ))
    from "group" g
    left join external_payments_config cfg on cfg.singleton
    where g.group_id = p_group_id
    and g.community_id = p_community_id
    and g.deleted = false;
$$ language sql;