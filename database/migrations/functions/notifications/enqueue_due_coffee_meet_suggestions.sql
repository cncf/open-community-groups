-- enqueue_due_coffee_meet_suggestions generates and enqueues due CoffeeMeet suggestions.
create or replace function enqueue_due_coffee_meet_suggestions(p_base_url text)
returns int as $$
declare
    v_base_url text;
    v_count int := 0;
    v_due record;
    v_found_suggestion boolean;
    v_interval interval;
    v_suggested record;
    v_template_data jsonb;
begin
    if not pg_try_advisory_xact_lock(hashtextextended('ocg:coffee-meet-enqueue', 0)) then
        return 0;
    end if;

    v_base_url := regexp_replace(coalesce(p_base_url, ''), '/+$', '');

    for v_due in
        select
            cms.group_id,
            cms.user_id,
            cms.frequency,
            cms.next_suggestion_at,
            g.name as group_name,
            g.slug as group_slug,
            g.slug_pretty as group_slug_pretty,
            a.name as alliance_name,
            s.theme
        from coffee_meet_subscription cms
        join group_member gm
            on gm.group_id = cms.group_id
            and gm.user_id = cms.user_id
        join "group" g on g.group_id = cms.group_id
        join alliance a using (alliance_id)
        left join lateral (
            select site.theme
            from site
            order by site.created_at desc
            limit 1
        ) s on true
        join "user" subscriber on subscriber.user_id = cms.user_id
        where cms.active = true
          and cms.next_suggestion_at <= current_timestamp
          and subscriber.email_verified = true
          and subscriber.coffee_meet_enabled = true
          and g.active = true
          and g.deleted = false
          and a.active = true
        order by cms.next_suggestion_at asc, cms.group_id, cms.user_id
        for update of cms skip locked
    loop
        select
            candidate.user_id,
            candidate.username,
            candidate.name,
            candidate.photo_url,
            candidate.title,
            candidate.company,
            candidate.bio,
            candidate.last_suggested_at
        into v_suggested
        from (
            select
                u.user_id,
                u.username,
                u.name,
                u.photo_url,
                u.title,
                u.company,
                u.bio,
                max(suggestion.created_at) as last_suggested_at
            from group_member gm
            join "user" u using (user_id)
            left join coffee_meet_suggestion suggestion
                on suggestion.group_id = gm.group_id
                and suggestion.subscriber_user_id = v_due.user_id
                and suggestion.suggested_user_id = gm.user_id
            where gm.group_id = v_due.group_id
              and gm.user_id <> v_due.user_id
              and u.email_verified = true
              and u.coffee_meet_enabled = true
            group by u.user_id
        ) candidate
        order by candidate.last_suggested_at asc nulls first, random()
        limit 1;
        v_found_suggestion := found;

        v_interval := case v_due.frequency
            when 'weekly' then interval '7 days'
            when 'biweekly' then interval '14 days'
            else interval '1 month'
        end;

        if not v_found_suggestion then
            update coffee_meet_subscription
            set
                next_suggestion_at = current_timestamp + v_interval,
                updated_at = current_timestamp
            where group_id = v_due.group_id
              and user_id = v_due.user_id;
        else
            insert into coffee_meet_suggestion (
                group_id,
                subscriber_user_id,
                suggested_user_id,
                frequency,
                suggested_for,
                notification_enqueued_at
            ) values (
                v_due.group_id,
                v_due.user_id,
                v_suggested.user_id,
                v_due.frequency,
                v_due.next_suggestion_at,
                current_timestamp
            );

            v_template_data := jsonb_strip_nulls(jsonb_build_object(
                'group_name', v_due.group_name,
                'frequency', v_due.frequency,
                'suggested_name', coalesce(v_suggested.name, v_suggested.username),
                'suggested_username', v_suggested.username,
                'suggested_photo_url', v_suggested.photo_url,
                'suggested_title', v_suggested.title,
                'suggested_company', v_suggested.company,
                'suggested_bio', v_suggested.bio,
                'suggested_profile_url', format(
                    '%s/profile/%s',
                    v_base_url,
                    v_suggested.username
                ),
                'group_url', format(
                    '%s/%s/group/%s',
                    v_base_url,
                    v_due.alliance_name,
                    coalesce(v_due.group_slug_pretty, v_due.group_slug)
                ),
                'dashboard_link', format('%s/dashboard/user?tab=coffee-meet', v_base_url),
                'theme', v_due.theme
            ));

            perform enqueue_notification(
                'coffee-meet-suggestion',
                v_template_data,
                '[]'::jsonb,
                array[v_due.user_id]
            );

            update coffee_meet_subscription
            set
                last_suggestion_at = current_timestamp,
                next_suggestion_at = current_timestamp + v_interval,
                updated_at = current_timestamp
            where group_id = v_due.group_id
              and user_id = v_due.user_id;

            v_count := v_count + 1;
        end if;
    end loop;

    return v_count;
end;
$$ language plpgsql;
