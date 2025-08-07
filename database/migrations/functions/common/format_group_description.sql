-- Formats the group description. If the description is null or contains placeholder
-- text, it will be set to null. Otherwise, it will clean up the description by removing
-- HTML tags, replacing non-breaking spaces and trimming it to a maximum length of 500.
create or replace function format_group_description(p_group json)
returns json as $$
    select json_strip_nulls(jsonb_set(
        p_group::jsonb,
        '{description}',
        case
            when p_group->>'description' is null
            then 'null'

            when p_group->>'description' like '%PLEASE ADD A DESCRIPTION HERE%'
              or p_group->>'description' like '%DESCRIPTION GOES HERE%'
              or p_group->>'description' like '%ADD DESCRIPTION HERE%'
              or p_group->>'description' like '%PLEASE UPDATE THE BELOW DESCRIPTION%'
              or p_group->>'description' like '%PLEASE UPDATE THE DESCRIPTION HERE%'
            then 'null'

            else to_jsonb(replace(regexp_replace(substring(p_group->>'description' for 500), E'<[^>]+>', '', 'gi'), '&nbsp;', ' '))
        end
    )::json)
$$ language sql;
