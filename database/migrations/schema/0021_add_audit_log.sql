-- Add append-only audit logging for dashboard and account mutations.

create table audit_log (
    audit_log_id uuid primary key default gen_random_uuid(),
    action text not null check (btrim(action) <> ''),
    created_at timestamptz default current_timestamp not null,
    resource_id uuid not null,
    resource_type text not null check (btrim(resource_type) <> ''),

    actor_user_id uuid,
    actor_username text check (actor_username is null or btrim(actor_username) <> ''),
    community_id uuid,
    details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
    event_id uuid,
    group_id uuid
);

create index audit_log_actor_user_id_created_at_idx on audit_log (actor_user_id, created_at desc);
create index audit_log_community_id_created_at_idx on audit_log (community_id, created_at desc);
create index audit_log_created_at_idx on audit_log (created_at desc);
create index audit_log_group_id_created_at_idx on audit_log (group_id, created_at desc);
create index audit_log_resource_type_resource_id_created_at_idx on audit_log (
    resource_type,
    resource_id,
    created_at desc
);
