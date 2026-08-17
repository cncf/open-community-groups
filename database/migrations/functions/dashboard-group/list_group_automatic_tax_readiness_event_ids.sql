-- Lists current paid events that require automatic-tax readiness for a group.
create or replace function list_group_automatic_tax_readiness_event_ids(
    p_community_id uuid,
    p_group_id uuid
)
returns uuid[] as $$
    select coalesce(
        array_agg(e.event_id order by e.event_id asc),
        '{}'::uuid[]
    )
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
    );
$$ language sql stable;
