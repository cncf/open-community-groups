-- Updates a CFS submission for an event.
create or replace function update_cfs_submission(
    p_reviewer_id uuid,
    p_event_id uuid,
    p_cfs_submission_id uuid,
    p_submission jsonb
)
returns boolean as $$
declare
    v_label_ids uuid[];
    v_notify boolean;
    v_previous_action_required_message text;
    v_previous_status_id text;
    v_rating_stars int;
begin
    -- Validate submission status provided
    if p_submission->>'status_id' is null
        or p_submission->>'status_id' not in (
            'approved',
            'information-requested',
            'not-reviewed',
            'rejected'
        ) then
        raise exception 'invalid submission status' using errcode = 'OCG01';
    end if;

    -- Parse the submitted labels, validated when they are synchronized
    if p_submission ? 'label_ids' then
        v_label_ids := array(
            select input_label_id::uuid
            from jsonb_array_elements_text(p_submission->'label_ids') as input_label_id
        );
    end if;

    -- Validate rating payload (`0` clears; `1`-`5` sets rating)
    if p_submission ? 'rating_stars' then
        v_rating_stars := (p_submission->>'rating_stars')::int;

        -- Reject ratings outside the supported range
        if v_rating_stars < 0 or v_rating_stars > 5 then
            raise exception 'invalid rating stars' using errcode = 'OCG01';
        end if;
    end if;

    -- Ensure submission exists and load previous state
    select cs.action_required_message, cs.status_id
    into v_previous_action_required_message, v_previous_status_id
    from cfs_submission cs
    where cs.cfs_submission_id = p_cfs_submission_id
    and cs.event_id = p_event_id
    and cs.status_id <> 'withdrawn'
    for update;

    -- Reject missing or withdrawn submissions
    if not found then
        raise exception 'submission not found' using errcode = 'OCG01';
    end if;

    -- Prevent status changes for linked submissions
    if p_submission->>'status_id' <> 'approved'
        and exists (
            select 1
            from session s
            where s.cfs_submission_id = p_cfs_submission_id
        ) then
        raise exception 'linked submissions must remain approved' using errcode = 'OCG01';
    end if;

    -- Update submission
    update cfs_submission set
        action_required_message = nullif(p_submission->>'action_required_message', ''),
        reviewed_by = p_reviewer_id,
        status_id = p_submission->>'status_id',
        updated_at = current_timestamp
    where cfs_submission_id = p_cfs_submission_id
    and event_id = p_event_id
    and status_id <> 'withdrawn';

    -- Replace submission labels
    if p_submission ? 'label_ids' then
        perform sync_cfs_submission_labels(p_cfs_submission_id, p_event_id, v_label_ids);
    end if;

    -- Upsert or remove the reviewer rating
    if p_submission ? 'rating_stars' then
        -- Remove the rating when it is cleared
        if v_rating_stars = 0 then
            delete from cfs_submission_rating
            where cfs_submission_id = p_cfs_submission_id
            and reviewer_id = p_reviewer_id;
        -- Store the reviewer rating
        else
            insert into cfs_submission_rating (
                comments,
                cfs_submission_id,
                reviewer_id,
                stars
            ) values (
                nullif(p_submission->>'rating_comment', ''),
                p_cfs_submission_id,
                p_reviewer_id,
                v_rating_stars
            )
            on conflict (cfs_submission_id, reviewer_id)
            do update set
                comments = excluded.comments,
                stars = excluded.stars,
                updated_at = current_timestamp;
        end if;
    end if;

    -- Determine if notification is necessary
    v_notify := (
        v_previous_status_id is distinct from (p_submission->>'status_id')
        or coalesce(v_previous_action_required_message, '')
            is distinct from coalesce(nullif(p_submission->>'action_required_message', ''), '')
    );

    -- Track the submission update
    perform insert_audit_log(
        'cfs_submission_updated',
        p_reviewer_id,
        'cfs_submission',
        p_cfs_submission_id,
        (
            select g.community_id
            from event e
            join "group" g on g.group_id = e.group_id
            where e.event_id = p_event_id
        ),
        (select group_id from event where event_id = p_event_id),
        p_event_id
    );

    -- Return whether the submitter should be notified
    return v_notify;
end;
$$ language plpgsql;
