-- Inserts a baseline group category row with placeholder plumbing.
create or replace function fx_group_category(
    p_group_category_id uuid,
    p_community_id uuid,
    p_overrides jsonb default '{}'::jsonb
)
returns void as $$
begin
    perform fx_insert_row('group_category', jsonb_build_object(
        'community_id', p_community_id,
        'group_category_id', p_group_category_id,
        'name', 'Fixture Group Category ' || p_group_category_id
    ) || p_overrides);
end;
$$ language plpgsql;
