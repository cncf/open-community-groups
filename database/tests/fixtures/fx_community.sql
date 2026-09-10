-- Inserts a baseline community row with placeholder plumbing.
create or replace function fx_community(
    p_community_id uuid,
    p_overrides jsonb default '{}'::jsonb
)
returns void as $$
begin
    perform fx_insert_row('community', jsonb_build_object(
        'banner_mobile_url', 'https://fixture.test/community-banner-mobile.png',
        'banner_url', 'https://fixture.test/community-banner.png',
        'community_id', p_community_id,
        'description', 'Fixture community',
        'display_name', 'Fixture Community ' || p_community_id,
        'logo_url', 'https://fixture.test/community-logo.png',
        'name', 'fixture-community-' || p_community_id
    ) || p_overrides);
end;
$$ language plpgsql;
