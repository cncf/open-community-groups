-- Queues a durable badge award for an explicit eligible recipient list.
create or replace function award_badge(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_badge_id uuid,
    p_user_ids uuid[],
    p_event_id uuid
)
returns json as $$
declare
    v_accepted_recipient_ids uuid[];
    v_actor_username text;
    v_badge badge%rowtype;
    v_community_name text;
    v_eligible_recipient_ids uuid[];
    v_group_name text;
    v_job_id uuid;
    v_recipient_user_ids uuid[];
    v_skipped_count integer;
    v_snapshot jsonb;
begin
    -- Lock and authorize the group boundary before accepting durable work
    select
        c.display_name,
        g.name
    into
        v_community_name,
        v_group_name
    from "group" g
    join community c using (community_id)
    where g.community_id = p_community_id
    and g.group_id = p_group_id
    and g.deleted = false
    for share of g;

    if not found then
        raise exception 'group not found';
    end if;
    if not user_has_group_permission(
        p_community_id,
        p_group_id,
        p_actor_user_id,
        'group.events.write'
    ) then
        raise exception 'badge permission denied' using errcode = 'insufficient_privilege';
    end if;

    -- Load the actor and definition snapshots used by deferred issuance
    select username
    into v_actor_username
    from "user"
    where user_id = p_actor_user_id;

    if not found then
        raise exception 'badge actor not found';
    end if;

    select *
    into v_badge
    from badge
    where badge_id = p_badge_id
    and group_id = p_group_id
    for share;

    if not found then
        raise exception 'badge not found';
    end if;

    -- Normalize duplicates before validating the complete requested set
    if p_user_ids is null
       or cardinality(p_user_ids) = 0
       or array_position(p_user_ids, null) is not null then
        raise exception 'badge recipients cannot be empty';
    end if;

    select array_agg(distinct recipients.user_id order by recipients.user_id)
    into v_recipient_user_ids
    from unnest(p_user_ids) as recipients(user_id);

    if p_event_id is not null then
        -- Lock the active event that defines contributor and attendee eligibility
        perform 1
        from event
        where event_id = p_event_id
        and group_id = p_group_id
        and canceled = false
        and deleted = false
        for share;

        if not found then
            raise exception 'event not found';
        end if;

        -- Resolve every verified event participant in canonical order
        select coalesce(array_agg(u.user_id order by u.user_id), '{}'::uuid[])
        into v_eligible_recipient_ids
        from "user" u
        where u.email_verified = true
        and u.user_id = any(v_recipient_user_ids)
        and (
            exists (
                select 1
                from event_attendee ea
                where ea.event_id = p_event_id
                and ea.status = 'confirmed'
                and ea.user_id = u.user_id
            )
            or exists (
                select 1
                from event_host eh
                where eh.event_id = p_event_id
                and eh.user_id = u.user_id
            )
            or exists (
                select 1
                from event_speaker es
                where es.event_id = p_event_id
                and es.user_id = u.user_id
            )
            or exists (
                select 1
                from session_speaker ss
                join session s using (session_id)
                where s.event_id = p_event_id
                and ss.user_id = u.user_id
            )
        );
    else
        -- Resolve every verified accepted group team member in canonical order
        select coalesce(array_agg(u.user_id order by u.user_id), '{}'::uuid[])
        into v_eligible_recipient_ids
        from group_team gt
        join "user" u using (user_id)
        where gt.accepted = true
        and gt.group_id = p_group_id
        and u.email_verified = true
        and u.user_id = any(v_recipient_user_ids);
    end if;

    if cardinality(v_eligible_recipient_ids) <> cardinality(v_recipient_user_ids) then
        raise exception 'badge recipient is not eligible';
    end if;

    -- Snapshot immutable definition and issuer fields before releasing request locks
    v_snapshot := jsonb_build_object(
        'criteria', v_badge.criteria,
        'description', v_badge.description,
        'image_file_name', v_badge.image_file_name,
        'issuer', jsonb_build_object(
            'community_id', p_community_id,
            'community_name', v_community_name,
            'group_id', p_group_id,
            'group_name', v_group_name
        ),
        'name', v_badge.name
    );

    -- Serialize same-definition handoffs so repeated requests cannot amplify queue load
    perform pg_advisory_xact_lock(
        hashtextextended('ocg:badge-award-queue:' || p_badge_id::text, 0)
    );

    -- Exclude current holders and recipients already owned by durable work
    select coalesce(array_agg(recipients.user_id order by recipients.user_id), '{}'::uuid[])
    into v_accepted_recipient_ids
    from unnest(v_recipient_user_ids) as recipients(user_id)
    where not exists (
        select 1
        from user_badge ub
        where ub.badge_id = p_badge_id
        and ub.revoked_at is null
        and ub.user_id = recipients.user_id
    )
    and not exists (
        select 1
        from badge_award_job_recipient bajr
        join badge_award_job baj using (badge_award_job_id)
        where baj.badge_id = p_badge_id
        and baj.status in ('failed', 'pending', 'processing')
        and bajr.user_id = recipients.user_id
    );

    v_skipped_count := cardinality(v_recipient_user_ids)
        - cardinality(v_accepted_recipient_ids);

    -- Persist one durable handoff when issuance work remains
    if cardinality(v_accepted_recipient_ids) > 0 then
        insert into badge_award_job (
            accepted_count,
            actor_username,
            badge_snapshot,
            community_id,
            group_id,
            recipient_count,
            skipped_count,

            actor_user_id,
            badge_id,
            event_id
        ) values (
            cardinality(v_accepted_recipient_ids),
            v_actor_username,
            v_snapshot,
            p_community_id,
            p_group_id,
            cardinality(v_recipient_user_ids),
            v_skipped_count,

            p_actor_user_id,
            p_badge_id,
            p_event_id
        )
        returning badge_award_job_id into v_job_id;

        insert into badge_award_job_recipient (
            badge_award_job_id,
            position,
            user_id
        )
        select
            v_job_id,
            (recipient.ordinality - 1)::integer,
            recipient.user_id
        from unnest(v_accepted_recipient_ids) with ordinality recipient(user_id, ordinality);
    end if;

    -- Return the existing frontend contract using accepted issuance counts
    return json_build_object(
        'awarded_count', cardinality(v_accepted_recipient_ids),
        'skipped_count', v_skipped_count
    );
end;
$$ language plpgsql;
