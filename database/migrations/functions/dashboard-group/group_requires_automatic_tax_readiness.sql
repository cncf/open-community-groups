-- Reports whether current paid events require automatic-tax readiness from a new sponsor.
create or replace function group_requires_automatic_tax_readiness(
    p_community_id uuid,
    p_group_id uuid
)
returns boolean as $$
    select cardinality(
        list_group_automatic_tax_readiness_event_ids(
            p_community_id,
            p_group_id
        )
    ) > 0;
$$ language sql stable;
