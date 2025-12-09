-- add_group adds a new group to the database.
create or replace function add_group(
    p_community_id uuid,
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
        v_slug := generate_slug(7);

        begin
            insert into "group" (
                community_id,
                name,
                slug,
                group_category_id,

                banner_url,
                city,
                country_code,
                country_name,
                description,
                description_short,
                extra_links,
                facebook_url,
                flickr_url,
                github_url,
                instagram_url,
                linkedin_url,
                location,
                logo_url,
                photos_urls,
                region_id,
                slack_url,
                state,
                tags,
                twitter_url,
                website_url,
                wechat_url,
                youtube_url
            ) values (
                p_community_id,
                p_group->>'name',
                v_slug,
                (p_group->>'category_id')::uuid,

                nullif(p_group->>'banner_url', ''),
                nullif(p_group->>'city', ''),
                nullif(p_group->>'country_code', ''),
                nullif(p_group->>'country_name', ''),
                nullif(p_group->>'description', ''),
                nullif(p_group->>'description_short', ''),
                p_group->'extra_links',
                nullif(p_group->>'facebook_url', ''),
                nullif(p_group->>'flickr_url', ''),
                nullif(p_group->>'github_url', ''),
                nullif(p_group->>'instagram_url', ''),
                nullif(p_group->>'linkedin_url', ''),
                case
                    when (p_group->>'latitude') is not null and (p_group->>'longitude') is not null
                    then ST_SetSRID(ST_MakePoint((p_group->>'longitude')::float, (p_group->>'latitude')::float), 4326)::geography
                    else null
                end,
                nullif(p_group->>'logo_url', ''),
                case when p_group->'photos_urls' is not null then array(select jsonb_array_elements_text(p_group->'photos_urls')) else null end,
                case when p_group->>'region_id' <> '' then (p_group->>'region_id')::uuid else null end,
                nullif(p_group->>'slack_url', ''),
                nullif(p_group->>'state', ''),
                case when p_group->'tags' is not null then array(select jsonb_array_elements_text(p_group->'tags')) else null end,
                nullif(p_group->>'twitter_url', ''),
                nullif(p_group->>'website_url', ''),
                nullif(p_group->>'wechat_url', ''),
                nullif(p_group->>'youtube_url', '')
            )
            returning group_id into v_group_id;

            return v_group_id;
        exception when unique_violation then
            v_retries := v_retries + 1;
            if v_retries >= v_max_retries then
                raise exception 'failed to generate unique slug after % attempts', v_max_retries;
            end if;
        end;
    end loop;
end;
$$ language plpgsql;
