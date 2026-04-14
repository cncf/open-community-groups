-- update_group updates an existing group's information.
create or replace function update_group(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_group jsonb
)
returns void as $$
declare
    v_payment_recipient_changed boolean := false;
    v_new_payment_recipient jsonb;
    v_previous_payment_recipient jsonb;
begin
    -- Retrieve the existing payment recipient to compare against the update payload
    select payment_recipient
    into v_previous_payment_recipient
    from "group"
    where group_id = p_group_id
    and community_id = p_community_id
    and deleted = false;

    -- Normalize the optional payment recipient before persisting it
    v_new_payment_recipient := case
        when p_group ? 'payment_recipient' then case
            when nullif(btrim(coalesce(p_group->'payment_recipient'->>'recipient_id', '')), '') is not null
            then jsonb_set(
                p_group->'payment_recipient',
                '{recipient_id}',
                to_jsonb(btrim(p_group->'payment_recipient'->>'recipient_id')),
                true
            )
            else null
        end
    end;

    -- Determine if the payment recipient is changing with the update
    v_payment_recipient_changed := p_group ? 'payment_recipient'
        and v_previous_payment_recipient is distinct from v_new_payment_recipient;

    -- Prevent clearing the recipient from breaking checkout for active ticketed events
    if v_payment_recipient_changed
       and v_new_payment_recipient is null
       and exists (
           select 1
           from event e
           join event_ticket_type ett on ett.event_id = e.event_id
           where e.group_id = p_group_id
           and e.canceled = false
           and e.deleted = false
       ) then
        raise exception 'ticketed events require a payment recipient';
    end if;

    -- Update the group fields from the payload
    update "group" set
        name = p_group->>'name',
        group_category_id = (p_group->>'category_id')::uuid,

        banner_mobile_url = nullif(p_group->>'banner_mobile_url', ''),
        banner_url = nullif(p_group->>'banner_url', ''),
        bluesky_url = nullif(p_group->>'bluesky_url', ''),
        city = nullif(p_group->>'city', ''),
        country_code = nullif(p_group->>'country_code', ''),
        country_name = nullif(p_group->>'country_name', ''),
        description = nullif(p_group->>'description', ''),
        description_short = nullif(p_group->>'description_short', ''),
        extra_links = p_group->'extra_links',
        facebook_url = nullif(p_group->>'facebook_url', ''),
        flickr_url = nullif(p_group->>'flickr_url', ''),
        github_url = nullif(p_group->>'github_url', ''),
        instagram_url = nullif(p_group->>'instagram_url', ''),
        linkedin_url = nullif(p_group->>'linkedin_url', ''),
        location = case
            when (p_group->>'latitude') is not null and (p_group->>'longitude') is not null
            then ST_SetSRID(ST_MakePoint((p_group->>'longitude')::float, (p_group->>'latitude')::float), 4326)::geography
            else null
        end,
        logo_url = nullif(p_group->>'logo_url', ''),
        payment_recipient = case
            when p_group ? 'payment_recipient' then v_new_payment_recipient
            else payment_recipient
        end,
        photos_urls = case
            when p_group ? 'photos_urls' and jsonb_typeof(p_group->'photos_urls') != 'null' then
                array(select jsonb_array_elements_text(p_group->'photos_urls'))
            else null
        end,
        region_id = case when p_group->>'region_id' <> '' then (p_group->>'region_id')::uuid else null end,
        slack_url = nullif(p_group->>'slack_url', ''),
        state = nullif(p_group->>'state', ''),
        tags = case
            when p_group ? 'tags' and jsonb_typeof(p_group->'tags') != 'null' then
                array(select jsonb_array_elements_text(p_group->'tags'))
            else null
        end,
        twitter_url = nullif(p_group->>'twitter_url', ''),
        website_url = nullif(p_group->>'website_url', ''),
        wechat_url = nullif(p_group->>'wechat_url', ''),
        youtube_url = nullif(p_group->>'youtube_url', '')
    where group_id = p_group_id
    and community_id = p_community_id
    and deleted = false;

    -- Ensure the target group exists and is active
    if not found then
        raise exception 'group not found or inactive';
    end if;

    -- Track the update
    perform insert_audit_log(
        'group_updated',
        p_actor_user_id,
        'group',
        p_group_id,
        p_community_id,
        p_group_id
    );

    -- If the payment recipient was changed, track that update as well
    if v_payment_recipient_changed then
        perform insert_audit_log(
            'group_payment_recipient_updated',
            p_actor_user_id,
            'group',
            p_group_id,
            p_community_id,
            p_group_id
        );
    end if;
end;
$$ language plpgsql;
