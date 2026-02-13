-- update_user_details updates a user's profile information.
create or replace function update_user_details(
    p_user_id uuid,
    p_user jsonb
) returns void as $$
    update "user"
    set
        name = p_user->>'name',
        bio = nullif(p_user->>'bio', ''),
        bluesky_url = nullif(p_user->>'bluesky_url', ''),
        city = nullif(p_user->>'city', ''),
        company = nullif(p_user->>'company', ''),
        country = nullif(p_user->>'country', ''),
        facebook_url = nullif(p_user->>'facebook_url', ''),
        interests = case
            when p_user ? 'interests' and jsonb_typeof(p_user->'interests') != 'null' then
                array(select jsonb_array_elements_text(p_user->'interests'))
            else null
        end,
        linkedin_url = nullif(p_user->>'linkedin_url', ''),
        photo_url = nullif(p_user->>'photo_url', ''),
        timezone = nullif(p_user->>'timezone', ''),
        title = nullif(p_user->>'title', ''),
        twitter_url = nullif(p_user->>'twitter_url', ''),
        website_url = nullif(p_user->>'website_url', '')
    where user_id = p_user_id;
$$ language sql;
