-- Returns whether the group's country is on the external-payments allowlist,
-- mirroring the country update_group would store: a null p_country_code keeps
-- the stored country, an empty string clears it. Missing, deleted, or
-- foreign-community groups return false.
create or replace function get_group_external_payments_eligibility(
    p_community_id uuid,
    p_group_id uuid,
    p_country_code text default null
)
returns boolean as $$
    select coalesce(
        (
            select is_country_external_payments_allowlisted(
                case
                    when p_country_code is null then g.country_code
                    else nullif(p_country_code, '')
                end
            )
            from "group" g
            where g.group_id = p_group_id
            and g.community_id = p_community_id
            and g.deleted = false
        ),
        false
    );
$$ language sql;
