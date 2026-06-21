-- Add alliance-level restriction for group team management.

alter table alliance
add column group_team_management_restricted boolean default false not null;
