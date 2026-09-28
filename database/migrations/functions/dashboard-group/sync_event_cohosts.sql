-- Synchronizes an event editor's requested co-host groups with current invitations.
create or replace function sync_event_cohosts(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_cohost_group_ids uuid[],
    p_expected_revision int
)
returns json as $$
declare
    v_added jsonb := '[]'::jsonb;
    v_current_group_ids uuid[];
    v_event event;
    v_group_id uuid;
    v_invitation_id uuid;
    v_prior_status text;
    v_removed jsonb := '[]'::jsonb;
    v_requested_group_ids uuid[] := array(
        select distinct group_id
        from unnest(coalesce(p_cohost_group_ids, '{}'::uuid[])) as requested(group_id)
        where group_id is not null
        order by group_id
    );
begin
    -- Lock and validate the editable owner event
    select e.*
    into v_event
    from event e
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.canceled = false
    and e.deleted = false
    for update of e;

    -- Reject inactive or cross-group events
    if not found then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Reject stale editor revisions
    if v_event.cohosts_revision is distinct from p_expected_revision then
        raise exception 'co-hosts changed since this page was loaded; reload to continue' using errcode = 'OCG01';
    end if;

    -- Reject selections beyond the supported bound
    if cardinality(v_requested_group_ids) > 10 then
        raise exception 'too many co-hosts' using errcode = 'OCG01';
    end if;

    -- Lock existing co-host rows in stable group order
    perform 1
    from event_cohost ec
    where ec.event_id = p_event_id
    order by ec.group_id
    for update of ec;

    -- Load the current active invitation set for published-event lock checks
    select coalesce(array_agg(ec.group_id order by ec.group_id), '{}'::uuid[])
    into v_current_group_ids
    from event_cohost ec
    where ec.event_id = p_event_id
    and ec.event_cohost_status_id in ('approved', 'pending');

    -- Reject real owner-side changes while the event is published
    if v_event.published and v_requested_group_ids <> v_current_group_ids then
        raise exception 'co-hosts cannot be changed while the event is published' using errcode = 'OCG01';
    end if;

    -- Reject self co-hosting before touching state
    if p_group_id = any(v_requested_group_ids) then
        raise exception 'event group cannot co-host its own event' using errcode = 'OCG01';
    end if;

    -- Reject missing, inactive, deleted, or inactive-community groups only for invitations being opened
    if exists (
        select 1
        from unnest(v_requested_group_ids) as requested(group_id)
        left join "group" g on g.group_id = requested.group_id
        left join community c on c.community_id = g.community_id
        where g.group_id is null
        or (
            not exists (
                select 1
                from event_cohost active_cohost
                where active_cohost.event_id = p_event_id
                and active_cohost.group_id = requested.group_id
                and active_cohost.event_cohost_status_id in ('approved', 'pending')
            )
            and (
                c.active = false
                or g.active = false
                or g.deleted = true
            )
        )
    ) then
        raise exception 'co-host group not found or inactive' using errcode = 'OCG01';
    end if;

    -- Remove active co-host rows omitted from the submitted selection
    for v_group_id, v_invitation_id, v_prior_status in
        select
            ec.group_id,
            ec.invitation_id,
            ec.event_cohost_status_id
        from event_cohost ec
        where ec.event_id = p_event_id
        and ec.event_cohost_status_id in ('approved', 'pending')
        and not (ec.group_id = any(v_requested_group_ids))
        order by ec.group_id
    loop
        -- Persist the owner removal
        update event_cohost
        set
            event_cohost_status_id = 'removed',
            responded_at = current_timestamp,
            responded_by = p_actor_user_id,
            updated_at = current_timestamp
        where event_id = p_event_id
        and group_id = v_group_id;

        -- Track and audit each removal
        v_removed := v_removed || jsonb_build_array(jsonb_build_object(
            'cohost_group_id', v_group_id,
            'event_id', p_event_id,
            'invitation_id', v_invitation_id
        ));

        perform insert_event_cohost_audit(
            'event_cohost_removed',
            p_actor_user_id,
            p_event_id,
            p_group_id,
            v_group_id,
            v_invitation_id,
            v_prior_status,
            'removed'
        );
    end loop;

    -- Insert or re-open every requested co-host that is not already active
    foreach v_group_id in array v_requested_group_ids
    loop
        -- Load the current row state for this requested group
        select
            ec.event_cohost_status_id,
            ec.invitation_id
        into
            v_prior_status,
            v_invitation_id
        from event_cohost ec
        where ec.event_id = p_event_id
        and ec.group_id = v_group_id;

        -- Skip unchanged active invitations
        if found and v_prior_status in ('approved', 'pending') then
            continue;
        end if;

        -- Create a first invitation
        if not found then
            insert into event_cohost (
                event_id,
                group_id,
                invited_by
            ) values (
                p_event_id,
                v_group_id,
                p_actor_user_id
            )
            returning invitation_id into v_invitation_id;

        -- Re-open a user-closed or owner-removed invitation
        elsif v_prior_status in ('canceled', 'rejected', 'removed') then
            update event_cohost
            set
                approved_at = null,
                event_cohost_status_id = 'pending',
                invitation_id = gen_random_uuid(),
                invited_at = current_timestamp,
                invited_by = p_actor_user_id,
                responded_at = null,
                responded_by = null,
                updated_at = current_timestamp
            where event_id = p_event_id
            and group_id = v_group_id
            returning invitation_id into v_invitation_id;

        -- Reject unreachable terminal rows on editable events
        else
            raise exception 'event co-host invitation cannot be reopened';
        end if;

        -- Track and audit each invitation
        v_added := v_added || jsonb_build_array(jsonb_build_object(
            'cohost_group_id', v_group_id,
            'event_id', p_event_id,
            'invitation_id', v_invitation_id
        ));

        perform insert_event_cohost_audit(
            'event_cohost_invited',
            p_actor_user_id,
            p_event_id,
            p_group_id,
            v_group_id,
            v_invitation_id,
            v_prior_status,
            'pending'
        );
    end loop;

    -- Advance the revision after any changed co-host row
    if jsonb_array_length(v_added) > 0 or jsonb_array_length(v_removed) > 0 then
        update event
        set cohosts_revision = cohosts_revision + 1
        where event_id = p_event_id
        returning * into v_event;
    end if;

    -- Return the stable synchronization contract
    return json_build_object(
        'added', v_added,
        'removed', v_removed,
        'revision', v_event.cohosts_revision
    );
end;
$$ language plpgsql;
