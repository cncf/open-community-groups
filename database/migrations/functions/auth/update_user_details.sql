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
        github_url = nullif(p_user->>'github_url', ''),
        interests = jsonb_text_array(p_user->'interests'),
        linkedin_url = nullif(p_user->>'linkedin_url', ''),
        mentorship_businesses = coalesce((p_user->>'mentorship_businesses')::boolean, false),
        mentorship_individuals = coalesce((p_user->>'mentorship_individuals')::boolean, false),
        mentorship_note = nullif(p_user->>'mentorship_note', ''),
        mentorship_price = nullif(p_user->>'mentorship_price', ''),
        optional_notifications_enabled = coalesce(
            (p_user->>'optional_notifications_enabled')::boolean,
            optional_notifications_enabled
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
