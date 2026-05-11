-- update_user_details updates a user's profile information.
create or replace function update_user_details(
    p_actor_user_id uuid,
    p_user jsonb
) returns void as $$
begin
    -- Update the user fields from the payload
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
        mass_notifications_enabled = coalesce(
            (p_user->>'mass_notifications_enabled')::boolean,
            mass_notifications_enabled
        ),
        photo_url = nullif(p_user->>'photo_url', ''),
        timezone = nullif(p_user->>'timezone', ''),
        title = nullif(p_user->>'title', ''),
        twitter_url = nullif(p_user->>'twitter_url', ''),
        website_url = nullif(p_user->>'website_url', '')
    where user_id = p_actor_user_id;

    -- Track the profile update
    perform insert_audit_log(
        'user_details_updated',
        p_actor_user_id,
        'user',
        p_actor_user_id
    );
end;
$$ language plpgsql;
