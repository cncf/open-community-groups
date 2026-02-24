-- Add meeting provider host user tracking for host pool slot allocation.
alter table meeting add column provider_host_user_id text check (btrim(provider_host_user_id) <> '');

-- Index for efficient querying of meetings by provider host user and provider ID.
create index meeting_meeting_provider_id_provider_host_user_id_idx
    on meeting (meeting_provider_id, provider_host_user_id);

-- Drop old add_meeting signature.
drop function if exists add_meeting(text, text, text, text, uuid, uuid);
