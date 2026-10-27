-- update_group updates an existing group's information.
create or replace function update_group(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_group jsonb
)
returns void as $$
declare
    v_external_payments_changed boolean := false;
    v_group "group";
    v_new_country_code text;
    v_new_external_payments_enabled boolean;
    v_new_external_payments_seller_display_name text;
    v_new_parent_group_id uuid;
    v_new_payment_recipient jsonb;
    v_new_utm_campaigns text[];
    v_new_utm_mediums text[];
    v_new_utm_sources text[];
    v_parent_group_id_present boolean := false;
    v_payment_recipient_changed boolean := false;
    v_payment_validation jsonb;
    v_provider_account_changed boolean := false;
    v_recipient_id text;
    v_recipient_provider text;
    v_recipient_seller_display_name text;
    v_utm_present boolean := false;
begin
    -- Lock and load existing values to compare against the update payload
    v_group := lock_active_group(p_community_id, p_group_id);

    -- Resolve the requested parent value
    v_parent_group_id_present := coalesce((p_group->>'parent_group_id_present')::boolean, false);
    v_new_parent_group_id := case
        -- Use the explicitly submitted parent, including an explicit clear
        when v_parent_group_id_present then nullif(p_group->>'parent_group_id', '')::uuid
        -- Preserve the parent omitted from a partial payload
        else v_group.parent_group_id
    end;

    -- Require permission on a newly selected parent, but not for no-op saves or clears
    if v_parent_group_id_present
       and v_new_parent_group_id is not null
       and v_new_parent_group_id is distinct from v_group.parent_group_id
       and not user_has_group_permission(
           p_community_id,
           v_new_parent_group_id,
           p_actor_user_id,
           'group.settings.write'
       ) then
        raise exception 'you must be able to manage the selected parent group' using errcode = 'OCG01';
    end if;

    -- Detect whether the payload addresses the UTM values
    v_utm_present := coalesce((p_group->>'utm_present')::boolean, false);

    -- Normalize the submitted UTM lists when the payload addressed them
    if v_utm_present then
        -- Read the submitted lists, treating omitted ones as cleared
        v_new_utm_campaigns := coalesce(jsonb_text_array(p_group->'utm_campaigns'), '{}');
        v_new_utm_mediums := coalesce(jsonb_text_array(p_group->'utm_mediums'), '{}');
        v_new_utm_sources := coalesce(jsonb_text_array(p_group->'utm_sources'), '{}');

        -- Reject extra mediums that are already accepted by default
        if exists (
            select 1
            from utm_medium um
            where um.utm_medium_id = any(v_new_utm_mediums)
        ) then
            raise exception 'utm mediums cannot include default mediums' using errcode = 'OCG01';
        end if;
    end if;

    -- Resolve the final country and external-payments toggle together
    v_new_country_code := case
        -- Use an explicitly submitted country
        when p_group ? 'country_code' then nullif(p_group->>'country_code', '')
        -- Preserve the country omitted from a partial payload
        else v_group.country_code
    end;
    v_new_external_payments_enabled := case
        -- Use an explicitly submitted toggle, treating an invalid value as off
        when p_group ? 'external_payments_enabled' then
            coalesce((p_group->>'external_payments_enabled')::boolean, false)
        -- Preserve the toggle omitted from a partial payload
        else v_group.external_payments_enabled
    end;
    v_new_external_payments_seller_display_name := case
        -- Use an explicitly submitted legal name, treating blank as a clear
        when p_group ? 'external_payments_seller_display_name' then
            nullif(btrim(p_group->>'external_payments_seller_display_name'), '')
        -- Preserve the legal name omitted from a partial payload
        else v_group.external_payments_seller_display_name
    end;
    v_external_payments_changed :=
        v_new_external_payments_enabled is distinct from v_group.external_payments_enabled
        or v_new_external_payments_seller_display_name
            is distinct from v_group.external_payments_seller_display_name;

    -- Require the legal name of the external payee while payloads addressing
    -- external payments keep the rail enabled
    if v_new_external_payments_enabled
       and v_new_external_payments_seller_display_name is null
       and (
           p_group ? 'external_payments_enabled'
           or p_group ? 'external_payments_seller_display_name'
       ) then
        raise exception 'external payments require the legal name of the organization collecting payments' using errcode = 'OCG01';
    end if;

    -- Read the submitted payment recipient fields, treating blank values as omitted
    if p_group ? 'payment_recipient' then
        v_recipient_id := nullif(btrim(p_group->'payment_recipient'->>'recipient_id'), '');
        v_recipient_provider := nullif(btrim(p_group->'payment_recipient'->>'provider'), '');
        v_recipient_seller_display_name := nullif(
            btrim(p_group->'payment_recipient'->>'seller_display_name'),
            ''
        );
    end if;

    -- Require the provider account and attendee-visible seller name together
    if p_group ? 'payment_recipient'
       and (
           (
               v_recipient_id is not null
               and (v_recipient_provider is null or v_recipient_seller_display_name is null)
           )
           or (v_recipient_seller_display_name is not null and v_recipient_id is null)
       ) then
        raise exception 'payment recipient account and seller name must be provided together' using errcode = 'OCG01';
    end if;

    -- Normalize the optional payment recipient before persisting it
    v_new_payment_recipient := case
        -- Store the trimmed recipient fields when an account is provided
        when v_recipient_id is not null then jsonb_build_object(
            'provider', v_recipient_provider,
            'recipient_id', v_recipient_id,
            'seller_display_name', v_recipient_seller_display_name
        )
        -- Treat an empty or omitted account as no recipient
        else null
    end;

    -- Determine if the payment recipient is changing with the update
    v_payment_recipient_changed := p_group ? 'payment_recipient'
        and v_group.payment_recipient is distinct from v_new_payment_recipient;
    v_provider_account_changed := v_payment_recipient_changed
        and v_new_payment_recipient is not null
        and (
            v_group.payment_recipient is null
            or v_group.payment_recipient->>'provider' is distinct from
                v_new_payment_recipient->>'provider'
            or v_group.payment_recipient->>'recipient_id' is distinct from
                v_new_payment_recipient->>'recipient_id'
        );

    -- Reject adding or changing a Stripe account while the resulting group
    -- country collects ticket payments outside the platform
    if v_provider_account_changed
       and is_country_external_payments_allowlisted(v_new_country_code) then
        raise exception 'stripe connected account cannot be added or changed for this group country' using errcode = 'OCG01';
    end if;

    -- Bind external provider validation to the payment state locked above
    if v_provider_account_changed then
        -- Read the validation snapshot captured by the provider check
        v_payment_validation := p_group->'_payment_validation';

        -- Reject validation snapshots that do not match the locked payment state
        if not payment_validation_snapshot_matches(
               v_payment_validation,
               v_group.payment_recipient,
               v_new_payment_recipient
           )
           or (
               cardinality(list_group_automatic_tax_readiness_event_ids(
                   p_community_id,
                   p_group_id
               )) > 0
           ) is distinct from (v_payment_validation->>'require_automatic_tax')::boolean
        then
            raise exception 'payment configuration changed during provider validation' using errcode = 'OCG01';
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
           and e.external_payment_url is null
           and is_event_paid_capable(e.event_id)
           and not event_is_past(e)
       ) then
        raise exception 'paid-capable events require a payment recipient' using errcode = 'OCG01';
    end if;

    -- Block account replacement while published manual-tax sales remain active
    if v_provider_account_changed
       and v_group.payment_recipient is not null
       and exists (
            select 1
            from event e
            where e.group_id = p_group_id
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.external_payment_url is null
            and e.tax_calculation_mode = 'manual'
            and is_event_paid_capable(e.event_id)
            and not event_is_past(e)
       ) then
        raise exception 'fiscal sponsor cannot be replaced while published manual-tax events are upcoming' using errcode = 'OCG01';
    end if;

    -- Keep upcoming published external sales on their payment rail while the
    -- group can still collect externally
    if v_group.external_payments_enabled
       and not v_new_external_payments_enabled
       and is_country_external_payments_allowlisted(v_group.country_code)
       and exists (
           select 1
           from event e
           where e.group_id = p_group_id
           and e.canceled = false
           and e.deleted = false
           and e.published = true
           and e.external_payment_url is not null
           and is_event_paid_capable(e.event_id)
           and not event_is_past(e)
       ) then
        raise exception 'external payments cannot be disabled while published external paid events are upcoming' using errcode = 'OCG01';
    end if;

    -- Reject enabling the toggle or moving off the allowlist while it stays on
    if v_new_external_payments_enabled
       and (
           not v_group.external_payments_enabled
           or v_new_country_code is distinct from v_group.country_code
       )
       and not is_country_external_payments_allowlisted(v_new_country_code) then
        raise exception 'external payments are not available for this group country' using errcode = 'OCG01';
    end if;

    -- Keep upcoming published external sales inside the group country
    if v_new_external_payments_enabled
       and (
           not v_group.external_payments_enabled
           or v_new_country_code is distinct from v_group.country_code
       )
       and exists (
           select 1
           from event e
           where e.group_id = p_group_id
           and e.canceled = false
           and e.deleted = false
           and e.published = true
           and e.external_payment_url is not null
           and upper(e.venue_country_code) is distinct from upper(v_new_country_code)
           and not event_is_past(e)
       ) then
        raise exception 'published external paid events require a venue in the group country' using errcode = 'OCG01';
    end if;

    -- Require draft manual-tax events to reselect rates in the new account
    if v_payment_recipient_changed
       and (
           coalesce(v_group.payment_recipient->>'provider', '') is distinct from
               coalesce(v_new_payment_recipient->>'provider', '')
           or coalesce(v_group.payment_recipient->>'recipient_id', '') is distinct from
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
        country_code = v_new_country_code,
        country_name = nullif(p_group->>'country_name', ''),
        description = nullif(p_group->>'description', ''),
        description_short = nullif(p_group->>'description_short', ''),
        extra_links = p_group->'extra_links',
        external_payments_enabled = v_new_external_payments_enabled,
        external_payments_seller_display_name = v_new_external_payments_seller_display_name,
        facebook_url = nullif(p_group->>'facebook_url', ''),
        flickr_url = nullif(p_group->>'flickr_url', ''),
        github_url = nullif(p_group->>'github_url', ''),
        instagram_url = nullif(p_group->>'instagram_url', ''),
        linkedin_url = nullif(p_group->>'linkedin_url', ''),
        location = jsonb_geography_point(p_group),
        logo_url = nullif(p_group->>'logo_url', ''),
        og_image_url = nullif(p_group->>'og_image_url', ''),
        parent_group_id = v_new_parent_group_id,
        payment_recipient = case
            -- Apply the normalized recipient when the payload addressed it
            when p_group ? 'payment_recipient' then v_new_payment_recipient
            -- Preserve the recipient omitted from a partial payload
            else payment_recipient
        end,
        photos_urls = jsonb_text_array(p_group->'photos_urls'),
        region_id = case
            -- Use a submitted region
            when p_group->>'region_id' <> '' then (p_group->>'region_id')::uuid
            -- Clear the region when it is empty or omitted
            else null
        end,
        slack_url = nullif(p_group->>'slack_url', ''),
        slug_pretty = nullif(btrim(p_group->>'slug_pretty'), ''),
        state = nullif(p_group->>'state', ''),
        tags = jsonb_text_array(p_group->'tags'),
        twitter_url = nullif(p_group->>'twitter_url', ''),
        utm_campaigns = case
            -- Apply the submitted campaigns when the payload addressed them
            when v_utm_present then v_new_utm_campaigns
            -- Preserve the campaigns omitted from a partial payload
            else utm_campaigns
        end,
        utm_mediums = case
            -- Apply the submitted mediums when the payload addressed them
            when v_utm_present then v_new_utm_mediums
            -- Preserve the mediums omitted from a partial payload
            else utm_mediums
        end,
        utm_sources = case
            -- Apply the submitted sources when the payload addressed them
            when v_utm_present then v_new_utm_sources
            -- Preserve the sources omitted from a partial payload
            else utm_sources
        end,
        website_url = nullif(p_group->>'website_url', ''),
        wechat_url = nullif(p_group->>'wechat_url', ''),
        youtube_url = nullif(p_group->>'youtube_url', '')
    where group_id = p_group_id;

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

    -- Track external-payments toggle and payee changes after the group update succeeds
    if v_external_payments_changed then
        perform insert_audit_log(
            'group_external_payments_updated',
            p_actor_user_id,
            'group',
            p_group_id,
            p_community_id,
            p_group_id,
            null,
            jsonb_strip_nulls(jsonb_build_object(
                'external_payments_enabled', v_new_external_payments_enabled,
                'external_payments_seller_display_name', v_new_external_payments_seller_display_name
            ))
        );
    end if;
end;
$$ language plpgsql;
