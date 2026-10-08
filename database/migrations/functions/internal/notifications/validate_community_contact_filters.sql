-- Validates community contact filters against the community they target.
create or replace function validate_community_contact_filters(
    p_community_id uuid,
    p_filters jsonb
)
returns void as $$
begin
    -- Look for group categories outside the community
    perform 1
    from jsonb_array_elements_text(coalesce(p_filters->'group_category_ids', '[]')) as input(value)
    where case
        when coalesce(pg_input_is_valid(input.value, 'uuid'), false) then not exists (
            select 1
            from group_category gc
            where gc.community_id = p_community_id
            and gc.group_category_id = input.value::uuid
        )
        else true
    end;

    -- Reject group categories outside the community
    if found then
        raise exception 'group category not found' using errcode = 'OCG01';
    end if;

    -- Look for region values that are neither the no-region option nor identifiers
    perform 1
    from jsonb_array_elements_text(coalesce(p_filters->'regions', '[]')) as input(value)
    where input.value is distinct from 'none'
    and not coalesce(pg_input_is_valid(input.value, 'uuid'), false);

    -- Reject malformed region values
    if found then
        raise exception 'invalid region' using errcode = 'OCG01';
    end if;

    -- Look for regions outside the community
    perform 1
    from jsonb_array_elements_text(coalesce(p_filters->'regions', '[]')) as input(value)
    where case
        when input.value = 'none' then false
        else not exists (
            select 1
            from region r
            where r.community_id = p_community_id
            and r.region_id = input.value::uuid
        )
    end;

    -- Reject regions outside the community
    if found then
        raise exception 'region not found' using errcode = 'OCG01';
    end if;

    -- Look for unknown group team roles
    perform 1
    from jsonb_array_elements_text(coalesce(p_filters->'roles', '[]')) as input(value)
    where not exists (
        select 1
        from group_role gr
        where gr.group_role_id = input.value
    );

    -- Reject unknown group team roles
    if found then
        raise exception 'group role not found' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;
