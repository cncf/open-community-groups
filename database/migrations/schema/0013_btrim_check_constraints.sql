-- Update CHECK constraints to use btrim() to reject whitespace-only strings
--
-- This migration updates all existing `check (field <> '')` constraints to
-- `check (btrim(field) <> '')` to reject strings that contain only whitespace.
-- It also adds some missing CHECK constraints.

-- =============================================================================
-- COMMUNITY TABLE
-- =============================================================================

alter table community drop constraint community_description_check;
alter table community add constraint community_description_check check (btrim(description) <> '');

alter table community drop constraint community_display_name_check;
alter table community add constraint community_display_name_check check (btrim(display_name) <> '');

alter table community drop constraint community_header_logo_url_check;
alter table community add constraint community_header_logo_url_check check (btrim(header_logo_url) <> '');

alter table community drop constraint community_host_check;
alter table community add constraint community_host_check check (btrim(host) <> '');

alter table community drop constraint community_name_check;
alter table community add constraint community_name_check check (btrim(name) <> '');

alter table community drop constraint community_title_check;
alter table community add constraint community_title_check check (btrim(title) <> '');

alter table community drop constraint community_ad_banner_link_url_check;
alter table community add constraint community_ad_banner_link_url_check check (btrim(ad_banner_link_url) <> '');

alter table community drop constraint community_ad_banner_url_check;
alter table community add constraint community_ad_banner_url_check check (btrim(ad_banner_url) <> '');

alter table community drop constraint community_copyright_notice_check;
alter table community add constraint community_copyright_notice_check check (btrim(copyright_notice) <> '');

alter table community drop constraint community_facebook_url_check;
alter table community add constraint community_facebook_url_check check (btrim(facebook_url) <> '');

alter table community drop constraint community_favicon_url_check;
alter table community add constraint community_favicon_url_check check (btrim(favicon_url) <> '');

alter table community drop constraint community_flickr_url_check;
alter table community add constraint community_flickr_url_check check (btrim(flickr_url) <> '');

alter table community drop constraint community_footer_logo_url_check;
alter table community add constraint community_footer_logo_url_check check (btrim(footer_logo_url) <> '');

alter table community drop constraint community_github_url_check;
alter table community add constraint community_github_url_check check (btrim(github_url) <> '');

alter table community drop constraint community_instagram_url_check;
alter table community add constraint community_instagram_url_check check (btrim(instagram_url) <> '');

alter table community drop constraint community_jumbotron_image_url_check;
alter table community add constraint community_jumbotron_image_url_check check (btrim(jumbotron_image_url) <> '');

alter table community drop constraint community_linkedin_url_check;
alter table community add constraint community_linkedin_url_check check (btrim(linkedin_url) <> '');

alter table community drop constraint community_new_group_details_check;
alter table community add constraint community_new_group_details_check check (btrim(new_group_details) <> '');

alter table community drop constraint community_og_image_url_check;
alter table community add constraint community_og_image_url_check check (btrim(og_image_url) <> '');

alter table community drop constraint community_slack_url_check;
alter table community add constraint community_slack_url_check check (btrim(slack_url) <> '');

alter table community drop constraint community_twitter_url_check;
alter table community add constraint community_twitter_url_check check (btrim(twitter_url) <> '');

alter table community drop constraint community_website_url_check;
alter table community add constraint community_website_url_check check (btrim(website_url) <> '');

alter table community drop constraint community_wechat_url_check;
alter table community add constraint community_wechat_url_check check (btrim(wechat_url) <> '');

alter table community drop constraint community_youtube_url_check;
alter table community add constraint community_youtube_url_check check (btrim(youtube_url) <> '');

-- =============================================================================
-- USER TABLE
-- =============================================================================

alter table "user" drop constraint user_auth_hash_check;
alter table "user" add constraint user_auth_hash_check check (btrim(auth_hash) <> '');

alter table "user" drop constraint user_email_check;
alter table "user" add constraint user_email_check check (btrim(email) <> '');

alter table "user" drop constraint user_username_check;
alter table "user" add constraint user_username_check check (btrim(username) <> '');

alter table "user" drop constraint user_bio_check;
alter table "user" add constraint user_bio_check check (btrim(bio) <> '');

alter table "user" drop constraint user_city_check;
alter table "user" add constraint user_city_check check (btrim(city) <> '');

alter table "user" drop constraint user_company_check;
alter table "user" add constraint user_company_check check (btrim(company) <> '');

alter table "user" drop constraint user_country_check;
alter table "user" add constraint user_country_check check (btrim(country) <> '');

alter table "user" drop constraint user_facebook_url_check;
alter table "user" add constraint user_facebook_url_check check (btrim(facebook_url) <> '');

alter table "user" drop constraint user_linkedin_url_check;
alter table "user" add constraint user_linkedin_url_check check (btrim(linkedin_url) <> '');

alter table "user" drop constraint user_password_check;
alter table "user" add constraint user_password_check check (btrim(password) <> '');

alter table "user" drop constraint user_photo_url_check;
alter table "user" add constraint user_photo_url_check check (btrim(photo_url) <> '');

alter table "user" drop constraint user_timezone_check;
alter table "user" add constraint user_timezone_check check (btrim(timezone) <> '');

alter table "user" drop constraint user_title_check;
alter table "user" add constraint user_title_check check (btrim(title) <> '');

alter table "user" drop constraint user_twitter_url_check;
alter table "user" add constraint user_twitter_url_check check (btrim(twitter_url) <> '');

alter table "user" drop constraint user_website_url_check;
alter table "user" add constraint user_website_url_check check (btrim(website_url) <> '');

-- =============================================================================
-- REGION TABLE
-- =============================================================================

alter table region drop constraint region_name_check;
alter table region add constraint region_name_check check (btrim(name) <> '');

alter table region drop constraint region_normalized_name_check;
alter table region add constraint region_normalized_name_check check (btrim(normalized_name) <> '');

-- =============================================================================
-- GROUP_CATEGORY TABLE
-- =============================================================================

alter table group_category drop constraint group_category_name_check;
alter table group_category add constraint group_category_name_check check (btrim(name) <> '');

alter table group_category drop constraint group_category_normalized_name_check;
alter table group_category add constraint group_category_normalized_name_check check (btrim(normalized_name) <> '');

-- =============================================================================
-- GROUP_ROLE TABLE (ADD MISSING)
-- =============================================================================

alter table group_role add constraint group_role_display_name_check check (btrim(display_name) <> '');

-- =============================================================================
-- GROUP TABLE
-- =============================================================================

alter table "group" drop constraint group_name_check;
alter table "group" add constraint group_name_check check (btrim(name) <> '');

alter table "group" drop constraint group_slug_check;
alter table "group" add constraint group_slug_check check (btrim(slug) <> '');

-- Add missing banner_url constraint
alter table "group" add constraint group_banner_url_check check (btrim(banner_url) <> '');

alter table "group" drop constraint group_city_check;
alter table "group" add constraint group_city_check check (btrim(city) <> '');

alter table "group" drop constraint group_country_code_check;
alter table "group" add constraint group_country_code_check check (btrim(country_code) <> '');

alter table "group" drop constraint group_country_name_check;
alter table "group" add constraint group_country_name_check check (btrim(country_name) <> '');

alter table "group" drop constraint group_description_check;
alter table "group" add constraint group_description_check check (btrim(description) <> '');

alter table "group" drop constraint group_description_short_check;
alter table "group" add constraint group_description_short_check check (btrim(description_short) <> '');

alter table "group" drop constraint group_facebook_url_check;
alter table "group" add constraint group_facebook_url_check check (btrim(facebook_url) <> '');

alter table "group" drop constraint group_flickr_url_check;
alter table "group" add constraint group_flickr_url_check check (btrim(flickr_url) <> '');

alter table "group" drop constraint group_github_url_check;
alter table "group" add constraint group_github_url_check check (btrim(github_url) <> '');

alter table "group" drop constraint group_instagram_url_check;
alter table "group" add constraint group_instagram_url_check check (btrim(instagram_url) <> '');

alter table "group" drop constraint group_linkedin_url_check;
alter table "group" add constraint group_linkedin_url_check check (btrim(linkedin_url) <> '');

alter table "group" drop constraint group_logo_url_check;
alter table "group" add constraint group_logo_url_check check (btrim(logo_url) <> '');

alter table "group" drop constraint group_slack_url_check;
alter table "group" add constraint group_slack_url_check check (btrim(slack_url) <> '');

alter table "group" drop constraint group_state_check;
alter table "group" add constraint group_state_check check (btrim(state) <> '');

alter table "group" drop constraint group_twitter_url_check;
alter table "group" add constraint group_twitter_url_check check (btrim(twitter_url) <> '');

alter table "group" drop constraint group_website_url_check;
alter table "group" add constraint group_website_url_check check (btrim(website_url) <> '');

alter table "group" drop constraint group_wechat_url_check;
alter table "group" add constraint group_wechat_url_check check (btrim(wechat_url) <> '');

alter table "group" drop constraint group_youtube_url_check;
alter table "group" add constraint group_youtube_url_check check (btrim(youtube_url) <> '');

-- =============================================================================
-- GROUP_SPONSOR TABLE
-- =============================================================================

alter table group_sponsor drop constraint group_sponsor_logo_url_check;
alter table group_sponsor add constraint group_sponsor_logo_url_check check (btrim(logo_url) <> '');

alter table group_sponsor drop constraint group_sponsor_name_check;
alter table group_sponsor add constraint group_sponsor_name_check check (btrim(name) <> '');

alter table group_sponsor drop constraint group_sponsor_website_url_check;
alter table group_sponsor add constraint group_sponsor_website_url_check check (btrim(website_url) <> '');

-- =============================================================================
-- EVENT_CATEGORY TABLE
-- =============================================================================

alter table event_category drop constraint event_category_name_check;
alter table event_category add constraint event_category_name_check check (btrim(name) <> '');

alter table event_category drop constraint event_category_slug_check;
alter table event_category add constraint event_category_slug_check check (btrim(slug) <> '');

-- =============================================================================
-- EVENT TABLE
-- =============================================================================

alter table event drop constraint event_description_check;
alter table event add constraint event_description_check check (btrim(description) <> '');

alter table event drop constraint event_name_check;
alter table event add constraint event_name_check check (btrim(name) <> '');

alter table event drop constraint event_slug_check;
alter table event add constraint event_slug_check check (btrim(slug) <> '');

alter table event drop constraint event_timezone_check;
alter table event add constraint event_timezone_check check (btrim(timezone) <> '');

alter table event drop constraint event_banner_url_check;
alter table event add constraint event_banner_url_check check (btrim(banner_url) <> '');

alter table event drop constraint event_description_short_check;
alter table event add constraint event_description_short_check check (btrim(description_short) <> '');

alter table event drop constraint event_logo_url_check;
alter table event add constraint event_logo_url_check check (btrim(logo_url) <> '');

alter table event drop constraint event_meetup_url_check;
alter table event add constraint event_meetup_url_check check (btrim(meetup_url) <> '');

alter table event drop constraint event_recording_url_check;
alter table event add constraint event_meeting_recording_url_check check (btrim(meeting_recording_url) <> '');

alter table event drop constraint event_streaming_url_check;
alter table event add constraint event_meeting_join_url_check check (btrim(meeting_join_url) <> '');

alter table event drop constraint event_meeting_error_check;
alter table event add constraint event_meeting_error_check check (btrim(meeting_error) <> '');

alter table event drop constraint event_venue_address_check;
alter table event add constraint event_venue_address_check check (btrim(venue_address) <> '');

alter table event drop constraint event_venue_city_check;
alter table event add constraint event_venue_city_check check (btrim(venue_city) <> '');

alter table event drop constraint event_venue_name_check;
alter table event add constraint event_venue_name_check check (btrim(venue_name) <> '');

alter table event drop constraint event_venue_zip_code_check;
alter table event add constraint event_venue_zip_code_check check (btrim(venue_zip_code) <> '');

-- =============================================================================
-- EVENT_SPONSOR TABLE
-- =============================================================================

alter table event_sponsor drop constraint event_sponsor_level_check;
alter table event_sponsor add constraint event_sponsor_level_check check (btrim(level) <> '');

-- =============================================================================
-- SESSION TABLE
-- =============================================================================

-- Add missing name constraint
alter table session add constraint session_name_check check (btrim(name) <> '');

alter table session drop constraint session_description_check;
alter table session add constraint session_description_check check (btrim(description) <> '');

alter table session drop constraint session_location_check;
alter table session add constraint session_location_check check (btrim(location) <> '');

alter table session drop constraint session_recording_url_check;
alter table session add constraint session_meeting_recording_url_check check (btrim(meeting_recording_url) <> '');

alter table session drop constraint session_streaming_url_check;
alter table session add constraint session_meeting_join_url_check check (btrim(meeting_join_url) <> '');

alter table session drop constraint session_meeting_error_check;
alter table session add constraint session_meeting_error_check check (btrim(meeting_error) <> '');

-- =============================================================================
-- NOTIFICATION_KIND TABLE
-- =============================================================================

alter table notification_kind drop constraint notification_kind_name_check;
alter table notification_kind add constraint notification_kind_name_check check (btrim(name) <> '');

-- =============================================================================
-- NOTIFICATION TABLE
-- =============================================================================

alter table notification drop constraint notification_error_check;
alter table notification add constraint notification_error_check check (btrim(error) <> '');

-- =============================================================================
-- LEGACY_EVENT_HOST TABLE
-- =============================================================================

alter table legacy_event_host drop constraint legacy_event_host_bio_check;
alter table legacy_event_host add constraint legacy_event_host_bio_check check (btrim(bio) <> '');

alter table legacy_event_host drop constraint legacy_event_host_name_check;
alter table legacy_event_host add constraint legacy_event_host_name_check check (btrim(name) <> '');

alter table legacy_event_host drop constraint legacy_event_host_photo_url_check;
alter table legacy_event_host add constraint legacy_event_host_photo_url_check check (btrim(photo_url) <> '');

alter table legacy_event_host drop constraint legacy_event_host_title_check;
alter table legacy_event_host add constraint legacy_event_host_title_check check (btrim(title) <> '');

-- =============================================================================
-- LEGACY_EVENT_SPEAKER TABLE
-- =============================================================================

alter table legacy_event_speaker drop constraint legacy_event_speaker_bio_check;
alter table legacy_event_speaker add constraint legacy_event_speaker_bio_check check (btrim(bio) <> '');

alter table legacy_event_speaker drop constraint legacy_event_speaker_name_check;
alter table legacy_event_speaker add constraint legacy_event_speaker_name_check check (btrim(name) <> '');

alter table legacy_event_speaker drop constraint legacy_event_speaker_photo_url_check;
alter table legacy_event_speaker add constraint legacy_event_speaker_photo_url_check check (btrim(photo_url) <> '');

alter table legacy_event_speaker drop constraint legacy_event_speaker_title_check;
alter table legacy_event_speaker add constraint legacy_event_speaker_title_check check (btrim(title) <> '');

-- =============================================================================
-- ATTACHMENT TABLE (ADD MISSING)
-- =============================================================================

alter table attachment drop constraint attachment_content_type_check;
alter table attachment add constraint attachment_content_type_check check (btrim(content_type) <> '');

alter table attachment add constraint attachment_file_name_check check (btrim(file_name) <> '');

alter table attachment add constraint attachment_hash_check check (btrim(hash) <> '');

-- =============================================================================
-- CUSTOM_NOTIFICATION TABLE
-- =============================================================================

alter table custom_notification drop constraint custom_notification_subject_check;
alter table custom_notification add constraint custom_notification_subject_check check (btrim(subject) <> '');

alter table custom_notification drop constraint custom_notification_body_check;
alter table custom_notification add constraint custom_notification_body_check check (btrim(body) <> '');

-- =============================================================================
-- MEETING_PROVIDER TABLE (ADD MISSING)
-- =============================================================================

alter table meeting_provider add constraint meeting_provider_display_name_check check (btrim(display_name) <> '');

-- =============================================================================
-- MEETING TABLE
-- =============================================================================

alter table meeting drop constraint meeting_join_url_check;
alter table meeting add constraint meeting_join_url_check check (btrim(join_url) <> '');

alter table meeting drop constraint meeting_provider_meeting_id_check;
alter table meeting add constraint meeting_provider_meeting_id_check check (btrim(provider_meeting_id) <> '');

alter table meeting drop constraint meeting_recording_url_check;
alter table meeting add constraint meeting_recording_url_check check (btrim(recording_url) <> '');
