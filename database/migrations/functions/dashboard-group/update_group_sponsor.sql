-- Updates an existing sponsor in the group.
create or replace function update_group_sponsor(
    p_group_id uuid,
    p_group_sponsor_id uuid,
    p_sponsor jsonb
)
returns void as $$
    update group_sponsor set
        level = p_sponsor->>'level',
        logo_url = p_sponsor->>'logo_url',
        name = p_sponsor->>'name',
        website_url = p_sponsor->>'website_url'
    where group_sponsor_id = p_group_sponsor_id
    and group_id = p_group_id;
$$ language sql;
