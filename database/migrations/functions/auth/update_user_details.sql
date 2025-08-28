-- update_user_details updates a user's profile information.
create or replace function update_user_details(
    p_user_id uuid,
    p_user jsonb
) returns void as $$
    update "user"
    set
        name = p_user->>'name',
        bio = p_user->>'bio',
        city = p_user->>'city',
        company = p_user->>'company',
        country = p_user->>'country',
        facebook_url = p_user->>'facebook_url',
        interests = case
            when p_user ? 'interests' and jsonb_typeof(p_user->'interests') != 'null' then 
                array(select jsonb_array_elements_text(p_user->'interests'))
            else null
        end,
        linkedin_url = p_user->>'linkedin_url',
        photo_url = p_user->>'photo_url',
        timezone = p_user->>'timezone',
        title = p_user->>'title',
        twitter_url = p_user->>'twitter_url',
        website_url = p_user->>'website_url'
    where user_id = p_user_id;
$$ language sql;
