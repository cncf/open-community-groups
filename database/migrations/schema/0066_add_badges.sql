-- Adds group badges, durable awards, and revocation status lists.

create table badge (
    badge_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    criteria text not null,
    description text not null,
    group_id uuid not null references "group",
    image_file_name text not null,
    name text not null,
    tsdoc tsvector not null
        generated always as (
            setweight(to_tsvector('simple', name), 'A') ||
            setweight(to_tsvector('simple', description), 'B') ||
            setweight(to_tsvector('simple', criteria), 'C')
        ) stored,

    constraint badge_badge_id_group_id_key unique (badge_id, group_id),
    constraint badge_criteria_chk check (
        btrim(criteria) <> ''
        and char_length(criteria) <= 10000
    ),
    constraint badge_description_chk check (
        btrim(description) <> ''
        and char_length(description) <= 10000
    ),
    constraint badge_image_file_name_chk check (
        char_length(image_file_name) <= 80
        and image_file_name ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'
    ),
    constraint badge_name_chk check (
        btrim(name) <> ''
        and char_length(name) <= 200
    )
);

create table badge_artwork (
    badge_artwork_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    file_name text not null,
    group_id uuid not null references "group",

    constraint badge_artwork_file_name_chk check (
        char_length(file_name) <= 80
        and file_name ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'
    ),
    constraint badge_artwork_group_file_name_key unique (group_id, file_name)
);

create table badge_award_job (
    badge_award_job_id uuid primary key default gen_random_uuid(),
    accepted_count integer not null check (accepted_count >= 0),
    actor_username text not null,
    awarded_count integer default 0 not null check (awarded_count >= 0),
    badge_snapshot jsonb not null check (jsonb_typeof(badge_snapshot) = 'object'),
    community_id uuid not null references community,
    created_at timestamptz default current_timestamp not null,
    failure_count integer default 0 not null check (failure_count >= 0),
    group_id uuid not null references "group",
    next_attempt_at timestamptz default current_timestamp not null,
    next_recipient_offset integer default 0 not null check (next_recipient_offset >= 0),
    recipient_count integer not null check (recipient_count > 0),
    skipped_count integer default 0 not null check (skipped_count >= 0),
    status text default 'pending' not null,
    updated_at timestamptz default current_timestamp not null,

    actor_user_id uuid references "user" on delete set null,
    badge_id uuid references badge on delete set null,
    claim_id uuid,
    claimed_at timestamptz,
    completed_at timestamptz,
    error text,
    event_id uuid references event on delete set null,

    constraint badge_award_job_claim_chk check (
        (
            status = 'processing'
            and claim_id is not null
            and claimed_at is not null
        )
        or (
            status <> 'processing'
            and claim_id is null
            and claimed_at is null
        )
    ),
    constraint badge_award_job_counts_chk check (
        accepted_count + skipped_count >= recipient_count
        and awarded_count + skipped_count <= recipient_count
        and next_recipient_offset <= accepted_count
        and (
            status <> 'completed'
            or (
                awarded_count + skipped_count = recipient_count
                and next_recipient_offset = accepted_count
            )
        )
    ),
    constraint badge_award_job_status_chk check (
        status in ('completed', 'failed', 'pending', 'processing')
    ),
    constraint badge_award_job_terminal_chk check (
        (
            status in ('completed', 'failed')
            and completed_at is not null
        )
        or (
            status in ('pending', 'processing')
            and completed_at is null
        )
    )
);

create table badge_award_job_recipient (
    badge_award_job_id uuid not null references badge_award_job on delete cascade,
    position integer not null check (position >= 0),

    user_id uuid references "user" on delete set null,

    constraint badge_award_job_recipient_pkey primary key (
        badge_award_job_id,
        position
    ),
    constraint badge_award_job_recipient_badge_award_job_id_user_id_key unique (
        badge_award_job_id,
        user_id
    )
);

create table badge_status_list (
    badge_status_list_id uuid primary key default gen_random_uuid(),
    allocation_offset integer default floor(random() * 131072)::integer not null,
    allocation_position integer default 0 not null,
    allocation_stride integer default (floor(random() * 65536)::integer * 2 + 1) not null,
    created_at timestamptz default current_timestamp not null,
    group_id uuid not null references "group",

    constraint badge_status_list_allocation_offset_chk check (
        allocation_offset between 0 and 131071
    ),
    constraint badge_status_list_allocation_position_chk check (
        allocation_position between 0 and 131072
    ),
    constraint badge_status_list_allocation_stride_chk check (
        allocation_stride between 1 and 131071
        and allocation_stride % 2 = 1
    ),
    constraint badge_status_list_badge_status_list_id_group_id_key unique (
        badge_status_list_id,
        group_id
    )
);

alter table event
add constraint event_event_id_group_id_key unique (event_id, group_id);

create table user_badge (
    user_badge_id uuid primary key default gen_random_uuid(),
    awarded_at timestamptz default current_timestamp not null,
    badge_status_list_id uuid not null,
    display_order integer not null check (display_order >= 0),
    group_id uuid not null references "group",
    is_listed boolean default true not null,
    snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
    status_list_index integer not null check (status_list_index between 0 and 131071),

    badge_id uuid,
    event_id uuid,
    revocation_reason text check (revocation_reason is null or btrim(revocation_reason) <> ''),
    revoked_at timestamptz,
    revoked_by_user_id uuid references "user" on delete set null,
    user_id uuid references "user" on delete set null,

    constraint user_badge_active_user_chk check (revoked_at is not null or user_id is not null),
    constraint user_badge_badge_id_group_id_fkey foreign key (
        badge_id,
        group_id
    ) references badge (badge_id, group_id) on delete set null (badge_id),
    constraint user_badge_badge_status_list_id_group_id_fkey foreign key (
        badge_status_list_id,
        group_id
    ) references badge_status_list (badge_status_list_id, group_id),
    constraint user_badge_event_id_group_id_fkey foreign key (
        event_id,
        group_id
    ) references event (event_id, group_id) on delete set null (event_id),
    constraint user_badge_status_list_index_key unique (
        badge_status_list_id,
        status_list_index
    )
);

create index badge_artwork_file_name_idx on badge_artwork (file_name);
create index badge_artwork_group_id_idx on badge_artwork (group_id);
create index badge_award_job_claimed_at_idx on badge_award_job (claimed_at)
    where status = 'processing';
create index badge_award_job_completed_at_idx on badge_award_job (completed_at)
    where status = 'completed';
create index badge_award_job_group_id_created_at_idx
on badge_award_job (group_id, created_at desc);
create index badge_award_job_pending_idx
on badge_award_job (next_attempt_at, created_at, badge_award_job_id)
    where status = 'pending';
create index badge_award_job_recipient_user_id_idx
on badge_award_job_recipient (user_id)
    where user_id is not null;
create index badge_group_id_idx on badge (group_id);
create index badge_image_file_name_idx on badge (image_file_name);
create index badge_status_list_available_idx
on badge_status_list (group_id, created_at desc)
    where allocation_position < 131072;
create index badge_status_list_group_id_idx on badge_status_list (group_id);
create index badge_tsdoc_idx on badge using gin (tsdoc);
create index user_badge_awarded_at_idx on user_badge (awarded_at);
create index user_badge_badge_id_idx on user_badge (badge_id);
create unique index user_badge_badge_id_user_id_active_idx on user_badge (badge_id, user_id)
    where revoked_at is null;
create index user_badge_event_id_idx on user_badge (event_id);
create index user_badge_group_id_awarded_at_idx on user_badge (group_id, awarded_at desc);
create index user_badge_snapshot_image_file_name_idx
on user_badge ((snapshot->>'image_file_name'));
create index user_badge_status_list_revoked_idx
on user_badge (badge_status_list_id, status_list_index)
    where revoked_at is not null;
create index user_badge_user_id_display_order_idx on user_badge (user_id, display_order)
    where revoked_at is null;
create index user_badge_user_id_listed_display_order_idx
on user_badge (user_id, display_order)
    where revoked_at is null and is_listed = true;

-- Protects immutable issuance fields and prevents revoked badges from returning active.
create function prevent_user_badge_revocation_reversal()
returns trigger as $$
begin
    -- Preserve the credential inputs captured at issuance
    if new.awarded_at is distinct from old.awarded_at
        or new.badge_status_list_id is distinct from old.badge_status_list_id
        or new.group_id is distinct from old.group_id
        or new.snapshot is distinct from old.snapshot
        or new.status_list_index is distinct from old.status_list_index
        or new.user_badge_id is distinct from old.user_badge_id
        or (
            new.badge_id is distinct from old.badge_id
            and not (old.badge_id is not null and new.badge_id is null)
        )
        or (
            new.event_id is distinct from old.event_id
            and not (old.event_id is not null and new.event_id is null)
        )
        or (
            new.user_id is distinct from old.user_id
            and not (old.user_id is not null and new.user_id is null)
        )
    then
        raise exception 'badge issuance fields cannot be changed';
    end if;

    -- Keep every revoked credential hidden from its holder profile
    if new.revoked_at is not null and new.is_listed then
        raise exception 'revoked badge cannot be listed';
    end if;

    -- Preserve the original private reason and actor after revocation
    if old.revoked_at is not null
        and (
            new.revocation_reason is distinct from old.revocation_reason
            or (
                new.revoked_by_user_id is distinct from old.revoked_by_user_id
                and not (
                    old.revoked_by_user_id is not null
                    and new.revoked_by_user_id is null
                )
            )
        )
    then
        raise exception 'badge revocation metadata cannot be changed';
    end if;

    -- Preserve the first durable revocation timestamp
    if old.revoked_at is not null
        and new.revoked_at is distinct from old.revoked_at
    then
        raise exception 'badge revocation cannot be changed';
    end if;

    return new;
end;
$$ language plpgsql;

create trigger prevent_user_badge_revocation_reversal
before update on user_badge
for each row execute function prevent_user_badge_revocation_reversal();

-- Revokes active credentials before their recipient association is removed.
create function revoke_user_badges_on_user_delete()
returns trigger as $$
begin
    -- Revoke every active award before the user foreign key is cleared
    with revoked as (
        update user_badge
        set
            is_listed = false,
            revocation_reason = 'recipient account deleted',
            revoked_at = current_timestamp,
            revoked_by_user_id = null
        where user_id = old.user_id
        and revoked_at is null
        returning event_id, group_id, snapshot, user_badge_id
    )
    insert into audit_log (
        action,
        actor_username,
        community_id,
        details,
        event_id,
        group_id,
        resource_id,
        resource_type
    )
    select
        'badge_revoked_account_deleted',
        old.username,
        g.community_id,
        jsonb_build_object(
            'badge_name', revoked.snapshot->>'name',
            'reason', 'recipient account deleted'
        ),
        revoked.event_id,
        revoked.group_id,
        revoked.user_badge_id,
        'user_badge'
    from revoked
    join "group" g using (group_id);

    return old;
end;
$$ language plpgsql;

create trigger revoke_user_badges_on_user_delete
before delete on "user"
for each row execute function revoke_user_badges_on_user_delete();

insert into notification_kind (name, optional_notification)
values
    ('badge-awarded', false),
    ('badge-revoked', false);
