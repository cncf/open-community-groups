-- add_group adds a new group to the database.
create or replace function add_group(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_group jsonb
)
returns uuid as $$
declare
    v_group_id uuid;
    v_slug text;
    v_retries int := 0;
    v_max_retries int := 10;
begin
    -- Insert group with unique slug generation and collision retry
    loop
        -- Generate a candidate slug for the new group
        v_slug := generate_slug(7);

        -- Retry generated slugs that match an existing pretty slug
        if exists (
            select 1
            from "group" g
            where g.alliance_id = p_alliance_id
            and (
                g.slug = v_slug
                or g.slug_pretty = v_slug
            )
        ) then
            v_retries := v_retries + 1;
            if v_retries >= v_max_retries then
                raise exception 'failed to generate unique slug after % attempts', v_max_retries;
            end if;
            continue;
        end if;

        begin
            insert into "group" (
                alliance_id,
                name,
                slug,
                group_category_id,

                banner_mobile_url,
                banner_url,
                bluesky_url,
                city,
                country_code,
                country_name,
                description,
                description_short,
                discord_url,
                extra_links,
                facebook_url,
                flickr_url,
                google_photos_url,
                github_url,
                instagram_url,
                linkedin_url,
                location,
                logo_url,
                membership_approval_required,
                mentorship_enabled,
                mock_interviews_enabled,
                og_image_url,
                photos_urls,
                region_id,
                slack_url,
                state,
                substack_url,
                tags,
                twitter_url,
                website_url,
                whatsapp_url,
                wechat_url,
                youtube_url
            ) values (
                p_alliance_id,
                p_group->>'name',
                v_slug,
                (p_group->>'category_id')::uuid,

                nullif(p_group->>'banner_mobile_url', ''),
                nullif(p_group->>'banner_url', ''),
                nullif(p_group->>'bluesky_url', ''),
                nullif(p_group->>'city', ''),
                nullif(p_group->>'country_code', ''),
                nullif(p_group->>'country_name', ''),
                nullif(p_group->>'description', ''),
                nullif(p_group->>'description_short', ''),
                nullif(p_group->>'discord_url', ''),
                p_group->'extra_links',
                nullif(p_group->>'facebook_url', ''),
                nullif(p_group->>'flickr_url', ''),
                nullif(p_group->>'google_photos_url', ''),
                nullif(p_group->>'github_url', ''),
                nullif(p_group->>'instagram_url', ''),
                nullif(p_group->>'linkedin_url', ''),
                jsonb_geography_point(p_group),
                nullif(p_group->>'logo_url', ''),
                coalesce((p_group->>'membership_approval_required')::boolean, false),
                coalesce((p_group->>'mentorship_enabled')::boolean, true),
                coalesce((p_group->>'mock_interviews_enabled')::boolean, true),
                nullif(p_group->>'og_image_url', ''),
                jsonb_text_array(p_group->'photos_urls'),
                case when p_group->>'region_id' <> '' then (p_group->>'region_id')::uuid else null end,
                nullif(p_group->>'slack_url', ''),
                nullif(p_group->>'state', ''),
                nullif(p_group->>'substack_url', ''),
                jsonb_text_array(p_group->'tags'),
                nullif(p_group->>'twitter_url', ''),
                nullif(p_group->>'website_url', ''),
                nullif(p_group->>'whatsapp_url', ''),
                nullif(p_group->>'wechat_url', ''),
                nullif(p_group->>'youtube_url', '')
            )
            returning group_id into v_group_id;

            -- Track the created group
            perform insert_audit_log(
                'group_added',
                p_actor_user_id,
                'group',
                v_group_id,
                p_alliance_id,
                v_group_id
            );

            -- Return immediately once insertion succeeds
            return v_group_id;
        exception when unique_violation then
            -- Retry slug generation when a collision occurs
            v_retries := v_retries + 1;
            if v_retries >= v_max_retries then
                raise exception 'failed to generate unique slug after % attempts', v_max_retries;
            end if;
        end;
    end loop;
end;
$$ language plpgsql;
