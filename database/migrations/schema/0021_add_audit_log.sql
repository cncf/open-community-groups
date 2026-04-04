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

-- Drop existing function signatures before recreating renamed input parameters.
drop function if exists accept_community_team_invitation(uuid, uuid);
drop function if exists accept_group_team_invitation(uuid, uuid);
drop function if exists accept_session_proposal_co_speaker_invitation(uuid, uuid);
drop function if exists activate_group(uuid, uuid, uuid);
drop function if exists add_community_team_member(uuid, uuid, uuid, text);
drop function if exists add_event(uuid, uuid, jsonb, jsonb);
drop function if exists add_event_category(uuid, uuid, jsonb);
drop function if exists add_group(uuid, uuid, jsonb);
drop function if exists add_group_category(uuid, uuid, jsonb);
drop function if exists add_group_sponsor(uuid, uuid, jsonb);
drop function if exists add_group_team_member(uuid, uuid, uuid, text);
drop function if exists add_region(uuid, uuid, jsonb);
drop function if exists add_session_proposal(uuid, jsonb);
drop function if exists cancel_event(uuid, uuid, uuid);
drop function if exists deactivate_group(uuid, uuid, uuid);
drop function if exists delete_community_team_member(uuid, uuid, uuid);
drop function if exists delete_event(uuid, uuid, uuid);
drop function if exists delete_event_category(uuid, uuid, uuid);
drop function if exists delete_group(uuid, uuid, uuid);
drop function if exists delete_group_category(uuid, uuid, uuid);
drop function if exists delete_group_sponsor(uuid, uuid, uuid);
drop function if exists delete_group_team_member(uuid, uuid, uuid);
drop function if exists delete_region(uuid, uuid, uuid);
drop function if exists delete_session_proposal(uuid, uuid);
drop function if exists manual_check_in_event(uuid, uuid, uuid, uuid);
drop function if exists publish_event(uuid, uuid, uuid);
drop function if exists reject_community_team_invitation(uuid, uuid);
drop function if exists reject_group_team_invitation(uuid, uuid);
drop function if exists reject_session_proposal_co_speaker_invitation(uuid, uuid);
drop function if exists resubmit_cfs_submission(uuid, uuid);
drop function if exists unpublish_event(uuid, uuid, uuid);
drop function if exists update_community(uuid, uuid, jsonb);
drop function if exists update_community_team_member_role(uuid, uuid, uuid, text);
drop function if exists update_event(uuid, uuid, uuid, jsonb, jsonb);
drop function if exists update_event_category(uuid, uuid, uuid, jsonb);
drop function if exists update_group(uuid, uuid, uuid, jsonb);
drop function if exists update_group_category(uuid, uuid, uuid, jsonb);
drop function if exists update_group_sponsor(uuid, uuid, uuid, jsonb);
drop function if exists update_group_team_member_role(uuid, uuid, uuid, text);
drop function if exists update_region(uuid, uuid, uuid, jsonb);
drop function if exists update_session_proposal(uuid, uuid, jsonb);
drop function if exists update_user_details(uuid, jsonb);
drop function if exists update_user_password(uuid, text);
drop function if exists withdraw_cfs_submission(uuid, uuid);
