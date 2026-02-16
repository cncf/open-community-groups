-- Updates a CFS submission for an event.
create or replace function update_cfs_submission(
    p_reviewer_id uuid,
    p_event_id uuid,
    p_cfs_submission_id uuid,
    p_submission jsonb
)
returns boolean as $$
declare
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
        raise exception 'invalid submission status';
    end if;

    -- Validate labels payload
    if p_submission ? 'label_ids' then
        if coalesce(jsonb_array_length(p_submission->'label_ids'), 0) > 10 then
            raise exception 'too many submission labels';
        end if;

        if p_submission->'label_ids' is not null then
            perform 1
            from jsonb_array_elements_text(p_submission->'label_ids') as input_label_id
            where not exists (
                select 1
                from event_cfs_label ecl
                where ecl.event_cfs_label_id = input_label_id::uuid
                and ecl.event_id = p_event_id
            );

            if found then
                raise exception 'invalid event CFS labels';
            end if;
        end if;
    end if;

    -- Validate rating payload (`0` clears; `1`-`5` sets rating)
    if p_submission ? 'rating_stars' then
        v_rating_stars := (p_submission->>'rating_stars')::int;

        if v_rating_stars < 0 or v_rating_stars > 5 then
            raise exception 'invalid rating stars';
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

    if not found then
        raise exception 'submission not found';
    end if;

    -- Prevent status changes for linked submissions
    if p_submission->>'status_id' <> 'approved'
        and exists (
            select 1
            from session s
            where s.cfs_submission_id = p_cfs_submission_id
        ) then
        raise exception 'linked submissions must remain approved';
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
        delete from cfs_submission_label
        where cfs_submission_id = p_cfs_submission_id;

        if p_submission->'label_ids' is not null then
            insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id)
            select p_cfs_submission_id, input_label_id::uuid
            from jsonb_array_elements_text(p_submission->'label_ids') as input_label_id
            group by input_label_id::uuid;
        end if;
    end if;

    -- Upsert or remove the reviewer rating
    if p_submission ? 'rating_stars' then
        if v_rating_stars = 0 then
            delete from cfs_submission_rating
            where cfs_submission_id = p_cfs_submission_id
            and reviewer_id = p_reviewer_id;
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

    return v_notify;
end;
$$ language plpgsql;
