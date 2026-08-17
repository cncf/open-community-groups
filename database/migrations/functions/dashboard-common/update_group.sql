-- update_group updates an existing group's information.
create or replace function update_group(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_group jsonb
)
returns void as $$
declare
    v_current_parent_group_id uuid;
    v_payment_recipient_changed boolean := false;
    v_payment_validation jsonb;
    v_parent_group_id_present boolean := false;
    v_provider_account_changed boolean := false;
    v_new_parent_group_id uuid;
    v_new_payment_recipient jsonb;
    v_previous_payment_recipient jsonb;
begin
    -- Retrieve existing values to compare against the update payload
    select
        parent_group_id,
        payment_recipient
    into
        v_current_parent_group_id,
        v_previous_payment_recipient
    from "group"
    where group_id = p_group_id
    and community_id = p_community_id
    and deleted = false
    for update;

    -- Resolve the requested parent value
    v_parent_group_id_present := coalesce((p_group->>'parent_group_id_present')::boolean, false);
    v_new_parent_group_id := case
        when v_parent_group_id_present then nullif(p_group->>'parent_group_id', '')::uuid
        else v_current_parent_group_id
    end;

    -- Require permission on a newly selected parent, but not for no-op saves or clears
    if v_parent_group_id_present
       and v_new_parent_group_id is not null
       and v_new_parent_group_id is distinct from v_current_parent_group_id
       and not user_has_group_permission(
           p_community_id,
           v_new_parent_group_id,
           p_actor_user_id,
           'group.settings.write'
       ) then
        raise exception 'you must be able to manage the selected parent group';
    end if;

    -- Require the provider account and attendee-visible seller name together
    if p_group ? 'payment_recipient'
       and nullif(btrim(coalesce(p_group->'payment_recipient'->>'recipient_id', '')), '')
           is not null
       and (
           nullif(btrim(coalesce(p_group->'payment_recipient'->>'provider', '')), '')
               is null
           or nullif(
               btrim(coalesce(p_group->'payment_recipient'->>'seller_display_name', '')),
               ''
           ) is null
       ) then
        raise exception 'payment recipient account and seller name must be provided together';
    end if;

    if p_group ? 'payment_recipient'
       and nullif(
           btrim(coalesce(p_group->'payment_recipient'->>'seller_display_name', '')),
           ''
       ) is not null
       and nullif(btrim(coalesce(p_group->'payment_recipient'->>'recipient_id', '')), '')
           is null then
        raise exception 'payment recipient account and seller name must be provided together';
    end if;

    -- Normalize the optional payment recipient before persisting it
    v_new_payment_recipient := case
        when p_group ? 'payment_recipient' then case
            when nullif(btrim(coalesce(p_group->'payment_recipient'->>'recipient_id', '')), '') is not null
            then jsonb_build_object(
                'provider', btrim(p_group->'payment_recipient'->>'provider'),
                'recipient_id', btrim(p_group->'payment_recipient'->>'recipient_id'),
                'seller_display_name',
                    btrim(p_group->'payment_recipient'->>'seller_display_name')
            )
            else null
        end
    end;

    -- Determine if the payment recipient is changing with the update
    v_payment_recipient_changed := p_group ? 'payment_recipient'
        and v_previous_payment_recipient is distinct from v_new_payment_recipient;
    v_provider_account_changed := v_payment_recipient_changed
        and v_new_payment_recipient is not null
        and (
            v_previous_payment_recipient is null
            or v_previous_payment_recipient->>'provider' is distinct from
                v_new_payment_recipient->>'provider'
            or v_previous_payment_recipient->>'recipient_id' is distinct from
                v_new_payment_recipient->>'recipient_id'
        );

    -- Bind external provider validation to the payment state locked above
    if v_provider_account_changed then
        v_payment_validation := p_group->'_payment_validation';
        if v_payment_validation is null
           or not (v_payment_validation ? 'expected_payment_recipient')
           or not (v_payment_validation ? 'validated_payment_recipient')
           or not (v_payment_validation ? 'require_automatic_tax')
           or v_previous_payment_recipient is distinct from nullif(
               v_payment_validation->'expected_payment_recipient',
               'null'::jsonb
           )
           or v_new_payment_recipient is distinct from nullif(
               v_payment_validation->'validated_payment_recipient',
               'null'::jsonb
           )
           or group_requires_automatic_tax_readiness(
               p_community_id,
               p_group_id
           ) is distinct from (v_payment_validation->>'require_automatic_tax')::boolean
        then
            raise exception 'payment configuration changed during provider validation';
        end if;
    end if;

    -- Prevent clearing the recipient from breaking checkout for active paid events
    if v_payment_recipient_changed
       and v_new_payment_recipient is null
       and exists (
           select 1
           from event e
           where e.group_id = p_group_id
           and e.canceled = false
           and e.deleted = false
           and e.published = true
           and is_event_paid_capable(e.event_id)
           and (
               coalesce(e.ends_at, e.starts_at) is null
               or coalesce(e.ends_at, e.starts_at) > current_timestamp
           )
       ) then
        raise exception 'paid-capable events require a payment recipient';
    end if;

    -- Block account replacement while published manual-tax sales remain active
    if v_provider_account_changed
       and v_previous_payment_recipient is not null
       and exists (
            select 1
            from event e
            where e.group_id = p_group_id
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.tax_calculation_mode = 'manual'
            and is_event_paid_capable(e.event_id)
            and (
                coalesce(e.ends_at, e.starts_at) is null
                or coalesce(e.ends_at, e.starts_at) > current_timestamp
            )
       ) then
        raise exception 'fiscal sponsor cannot be replaced while published manual-tax events are upcoming';
    end if;

    -- Require draft manual-tax events to reselect rates in the new account
    if v_payment_recipient_changed
       and (
           coalesce(v_previous_payment_recipient->>'provider', '') is distinct from
               coalesce(v_new_payment_recipient->>'provider', '')
           or coalesce(v_previous_payment_recipient->>'recipient_id', '') is distinct from
               coalesce(v_new_payment_recipient->>'recipient_id', '')
       ) then
        update event
        set manual_tax_rate_ids = '{}'::text[]
        where group_id = p_group_id
        and canceled = false
        and deleted = false
        and published = false
        and tax_calculation_mode = 'manual';
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
        location = jsonb_geography_point(p_group),
        logo_url = nullif(p_group->>'logo_url', ''),
        og_image_url = nullif(p_group->>'og_image_url', ''),
        parent_group_id = case
            when v_parent_group_id_present then v_new_parent_group_id
            else parent_group_id
        end,
        payment_recipient = case
            when p_group ? 'payment_recipient' then v_new_payment_recipient
            else payment_recipient
        end,
        photos_urls = jsonb_text_array(p_group->'photos_urls'),
        region_id = case when p_group->>'region_id' <> '' then (p_group->>'region_id')::uuid else null end,
        slack_url = nullif(p_group->>'slack_url', ''),
        slug_pretty = nullif(btrim(p_group->>'slug_pretty'), ''),
        state = nullif(p_group->>'state', ''),
        tags = jsonb_text_array(p_group->'tags'),
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
