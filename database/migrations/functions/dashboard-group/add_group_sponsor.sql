-- Adds a new sponsor to the group.
create or replace function add_group_sponsor(
    p_group_id uuid,
    p_sponsor jsonb
)
returns uuid as $$
    insert into group_sponsor (
        group_id,
        level,
        logo_url,
        name,

        website_url
    ) values (
        p_group_id,
        p_sponsor->>'level',
        p_sponsor->>'logo_url',
        p_sponsor->>'name',

        p_sponsor->>'website_url'
    )
    returning group_sponsor_id;
$$ language sql;
