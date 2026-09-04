-- Inserts a baseline group row with placeholder plumbing.
create or replace function fx_group(
    p_group_id uuid,
    p_community_id uuid,
    p_group_category_id uuid,
    p_overrides jsonb default '{}'::jsonb
)
returns void as $$
begin
    perform fx_insert_row('"group"', jsonb_build_object(
        'community_id', p_community_id,
        'group_category_id', p_group_category_id,
        'group_id', p_group_id,
        'name', 'Fixture Group',
        'slug', 'fixture-group-' || p_group_id
    ) || p_overrides);
end;
$$ language plpgsql;
