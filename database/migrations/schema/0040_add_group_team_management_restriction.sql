-- Add community-level restriction for group team management.

alter table community
add column group_team_management_restricted boolean default false not null;
