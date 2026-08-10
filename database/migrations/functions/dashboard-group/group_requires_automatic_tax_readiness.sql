-- Reports whether current paid events require automatic-tax readiness from a new sponsor.
create or replace function group_requires_automatic_tax_readiness(
    p_community_id uuid,
    p_group_id uuid
)
returns boolean as $$
    select exists (
        select 1
        from "group" g
        join event e using (group_id)
        where g.community_id = p_community_id
        and g.group_id = p_group_id
        and g.deleted = false
        and e.canceled = false
        and e.deleted = false
        and e.published = true
        and e.tax_calculation_mode = 'automatic'
        and is_event_paid_capable(e.event_id)
        and (
            coalesce(e.ends_at, e.starts_at) is null
            or coalesce(e.ends_at, e.starts_at) > current_timestamp
        )
    );
$$ language sql stable;
