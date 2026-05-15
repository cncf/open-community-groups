//! Event preview templates and types for the group dashboard.

use askama::Template;
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::templates::filters;

// Pages templates.

/// Event preview modal template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/event_preview.html")]
pub(crate) struct Page {
    /// Prepared event preview data rendered in the modal.
    pub event: Event,
}

// Types.

/// Prepared view model for rendering the event preview.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct Event {
    /// Banner image URL selected for the preview.
    pub banner_url: Option<String>,
    /// Community display name.
    pub community_display_name: Option<String>,
    /// Event description.
    pub description: Option<String>,
    /// Event-level hosts.
    pub hosts: Vec<ContextPerson>,
    /// Submitted editor state used to build the preview.
    pub input: Input,
    /// Event kind display label.
    pub kind_label: Option<String>,
    /// Logo image URL selected for the preview.
    pub logo_url: Option<String>,
    /// Missing or incomplete fields to highlight.
    pub missing_fields: Vec<String>,
    /// Event photo URLs.
    pub photos: Vec<String>,
    /// Event sessions.
    pub sessions: Vec<Session>,
    /// Event-level speakers.
    pub speakers: Vec<ContextPerson>,
    /// Event sponsors.
    pub sponsors: Vec<ContextSponsor>,
    /// Configured public URL, when the event already has one.
    pub public_url: Option<String>,
    /// Venue or location label.
    pub venue_label: Option<String>,
}

impl Event {
    /// Returns the configured capacity label or an unlimited fallback.
    pub(crate) fn capacity_label(&self) -> String {
        normalize_text(self.input.capacity.clone()).unwrap_or_else(|| "Unlimited".to_string())
    }

    /// Returns the CFS date range label.
    pub(crate) fn cfs_date_label(&self) -> String {
        let starts_at = parse_datetime(self.input.cfs_starts_at.as_deref());
        let ends_at = parse_datetime(self.input.cfs_ends_at.as_deref());

        match (starts_at, ends_at) {
            (Some(starts_at), Some(ends_at)) => format!(
                "{} - {}",
                starts_at.format("%b %-e, %Y %-I:%M %p"),
                ends_at.format("%b %-e, %Y %-I:%M %p")
            ),
            (Some(starts_at), None) => format!("Opens {}", starts_at.format("%b %-e, %Y %-I:%M %p")),
            (None, Some(ends_at)) => format!("Closes {}", ends_at.format("%b %-e, %Y %-I:%M %p")),
            (None, None) => "Missing CFS window".to_string(),
        }
    }

    /// Returns the event date display label.
    pub(crate) fn date_label(&self) -> String {
        match parse_datetime(self.input.starts_at.as_deref()) {
            Some(starts_at) => starts_at.format("%B %-e, %Y").to_string(),
            None => "Missing start date".to_string(),
        }
    }

    /// Returns the event group display label.
    pub(crate) fn group_name(&self) -> String {
        self.input
            .context()
            .group
            .and_then(|group| first_text([group.name.as_deref(), group.slug.as_deref()]))
            .unwrap_or_else(|| "Current group".to_string())
    }

    /// Returns true when CFS details should be shown.
    pub(crate) fn has_cfs(&self) -> bool {
        option_truthy(self.input.cfs_enabled.as_deref())
    }

    /// Returns whether the event includes an online meeting component.
    pub(crate) fn has_online_component(&self) -> bool {
        matches!(
            normalize_text(self.input.kind_id.clone()).as_deref(),
            Some("virtual" | "hybrid")
        )
    }

    /// Returns true when the event has configured speakers, hosts, or sponsors.
    pub(crate) fn has_people_or_sponsors(&self) -> bool {
        !self.hosts.is_empty() || !self.speakers.is_empty() || !self.sponsors.is_empty()
    }

    /// Returns whether the event includes an in-person venue component.
    pub(crate) fn has_venue_component(&self) -> bool {
        matches!(
            normalize_text(self.input.kind_id.clone()).as_deref(),
            Some("in-person" | "hybrid")
        )
    }

    /// Returns the event kind label or a missing-field placeholder.
    pub(crate) fn kind_display_label(&self) -> String {
        self.kind_label
            .clone()
            .unwrap_or_else(|| "Missing event type".to_string())
    }

    /// Returns the event title or a missing-field placeholder.
    pub(crate) fn name_label(&self) -> String {
        normalize_text(self.input.name.clone()).unwrap_or_else(|| "Missing event name".to_string())
    }

    /// Returns the event time display label.
    pub(crate) fn time_label(&self) -> String {
        let starts_at = parse_datetime(self.input.starts_at.as_deref());
        let ends_at = parse_datetime(self.input.ends_at.as_deref());
        let timezone = normalize_text(self.input.timezone.clone()).unwrap_or_default();

        match (starts_at, ends_at) {
            (Some(starts_at), Some(ends_at)) if starts_at.date() == ends_at.date() => {
                format!(
                    "{} - {} {}",
                    starts_at.format("%-I:%M %p"),
                    ends_at.format("%-I:%M %p"),
                    timezone
                )
            }
            (Some(starts_at), Some(ends_at)) => {
                format!(
                    "{} - {} {}",
                    starts_at.format("%b %-e, %-I:%M %p"),
                    ends_at.format("%b %-e, %-I:%M %p"),
                    timezone
                )
            }
            (Some(starts_at), None) => format!("{} {}", starts_at.format("%-I:%M %p"), timezone),
            (None, _) => "Missing start time".to_string(),
        }
    }
}

impl From<Input> for Event {
    /// Builds display-oriented preview data from submitted editor state.
    fn from(input: Input) -> Self {
        // Load display-only context supplied by the dashboard editor
        let context = input.context();

        // Resolve branding, taxonomy, and public URL fallbacks
        let banner_url = first_text([
            input.banner_url.as_deref(),
            context.group.as_ref().and_then(|group| group.banner_url.as_deref()),
            context
                .community
                .as_ref()
                .and_then(|community| community.banner_url.as_deref()),
        ]);
        let community_display_name = first_text([
            context
                .community
                .as_ref()
                .and_then(|community| community.display_name.as_deref()),
            context
                .community
                .as_ref()
                .and_then(|community| community.name.as_deref()),
        ]);
        let kind_label = first_text([context.kind_label.as_deref(), input.kind_id.as_deref()]);
        let logo_url = first_text([
            input.logo_url.as_deref(),
            context.group.as_ref().and_then(|group| group.logo_url.as_deref()),
            context
                .community
                .as_ref()
                .and_then(|community| community.logo_url.as_deref()),
        ]);
        let public_url = normalize_text(context.public_url.clone());

        // Normalize submitted collections for rendering
        let photos = input
            .photos_urls
            .clone()
            .unwrap_or_default()
            .into_iter()
            .filter_map(|value| normalize_text(Some(value)))
            .collect();
        let sessions = build_sessions(
            input.sessions.as_deref(),
            context.sessions.as_slice(),
            input.timezone.as_deref(),
        );

        // Derive location and missing-field display state
        let venue_label = build_location(&input);
        let missing_fields = build_missing_fields(&input, &context, venue_label.as_deref());

        // Assemble the render model
        Self {
            banner_url,
            community_display_name,
            description: normalize_text(input.description.clone()),
            hosts: context.hosts.clone(),
            input,
            kind_label,
            logo_url,
            missing_fields,
            photos,
            public_url,
            sessions,
            speakers: context.speakers.clone(),
            sponsors: context.sponsors.clone(),
            venue_label,
        }
    }
}

/// Prepared preview session data.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct Session {
    /// Session description.
    pub description: Option<String>,
    /// Session date label.
    pub date_label: String,
    /// Session kind label.
    pub kind_label: Option<String>,
    /// Session location label.
    pub location: Option<String>,
    /// Session name.
    pub name: Option<String>,
    /// Session online meeting label.
    pub online_label: Option<String>,
    /// Session speakers.
    pub speakers: Vec<ContextPerson>,
    /// Session time label.
    pub time_label: String,
}

impl Session {
    /// Returns the session kind label or a missing-field placeholder.
    pub(crate) fn kind_display_label(&self) -> String {
        self.kind_label
            .clone()
            .unwrap_or_else(|| "Missing session type".to_string())
    }

    /// Returns the session display name or a missing-field placeholder.
    pub(crate) fn name_label(&self) -> String {
        self.name
            .clone()
            .unwrap_or_else(|| "Missing session name".to_string())
    }
}

// Input types.

/// Submitted event editor payload accepted by the preview endpoint.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct Input {
    /// Event category identifier from the editor.
    pub category_id: Option<String>,
    /// Call for speakers description.
    pub cfs_description: Option<String>,
    /// Whether call for speakers is enabled.
    pub cfs_enabled: Option<String>,
    /// Call for speakers close time.
    pub cfs_ends_at: Option<String>,
    /// Call for speakers open time.
    pub cfs_starts_at: Option<String>,
    /// Event description.
    pub description: Option<String>,
    /// Event type identifier.
    pub kind_id: Option<String>,
    /// Event name.
    pub name: Option<String>,
    /// Timezone selected for the event.
    pub timezone: Option<String>,

    /// Attendee capacity configured in the editor.
    pub capacity: Option<String>,
    /// Event banner image URL.
    pub banner_url: Option<String>,
    /// Event end time.
    pub ends_at: Option<String>,
    /// Event logo image URL.
    pub logo_url: Option<String>,
    /// Meeting join instructions.
    pub meeting_join_instructions: Option<String>,
    /// Meeting join URL.
    pub meeting_join_url: Option<String>,
    /// Whether an automatic meeting was requested.
    pub meeting_requested: Option<String>,
    /// Event gallery image URLs.
    pub photos_urls: Option<Vec<String>>,
    /// Preview-only JSON context provided by the dashboard page.
    pub preview_context: Option<String>,
    /// Event sessions configured in the editor.
    pub sessions: Option<Vec<InputSession>>,
    /// Event start time.
    pub starts_at: Option<String>,
    /// Venue address.
    pub venue_address: Option<String>,
    /// Venue city.
    pub venue_city: Option<String>,
    /// Venue country code.
    pub venue_country_code: Option<String>,
    /// Venue country name.
    pub venue_country_name: Option<String>,
    /// Venue name.
    pub venue_name: Option<String>,
    /// Venue state or province.
    pub venue_state: Option<String>,
    /// Venue zip code.
    pub venue_zip_code: Option<String>,
}

impl Input {
    /// Parses display-only JSON context from the form payload.
    pub(crate) fn context(&self) -> Context {
        self.preview_context
            .as_deref()
            .and_then(|value| serde_json::from_str(value).ok())
            .unwrap_or_default()
    }
}

/// Tolerant preview-only session editor payload.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct InputSession {
    /// Session description.
    pub description: Option<String>,
    /// Session end time.
    pub ends_at: Option<String>,
    /// Session type identifier.
    pub kind: Option<String>,
    /// Session location.
    pub location: Option<String>,
    /// Session meeting instructions.
    pub meeting_join_instructions: Option<String>,
    /// Session meeting URL.
    pub meeting_join_url: Option<String>,
    /// Whether an automatic meeting was requested.
    pub meeting_requested: Option<String>,
    /// Session name.
    pub name: Option<String>,
    /// Session speakers submitted in the form.
    pub speakers: Option<Vec<InputSessionSpeaker>>,
    /// Session start time.
    pub starts_at: Option<String>,
}

/// Tolerant preview-only session speaker payload.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct InputSessionSpeaker {
    /// Whether the speaker is featured.
    pub featured: Option<String>,
    /// Speaker user identifier.
    pub user_id: Option<String>,
}

// Context types.

/// Preview-only JSON context provided by dashboard JavaScript.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct Context {
    /// Category display label selected in the editor.
    pub category_label: Option<String>,
    /// Community details for fallback branding.
    pub community: Option<ContextCommunity>,
    /// Group details for fallback branding.
    pub group: Option<ContextGroup>,
    /// Event-level hosts selected in the editor.
    #[serde(default)]
    pub hosts: Vec<ContextPerson>,
    /// Event type display label selected in the editor.
    pub kind_label: Option<String>,
    /// Public event URL when an existing event has one.
    pub public_url: Option<String>,
    /// Event sessions with display-only speaker data.
    #[serde(default)]
    pub sessions: Vec<ContextSession>,
    /// Event-level speakers selected in the editor.
    #[serde(default)]
    pub speakers: Vec<ContextPerson>,
    /// Event sponsors selected in the editor.
    #[serde(default)]
    pub sponsors: Vec<ContextSponsor>,
}

/// Preview community display context.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ContextCommunity {
    /// Community banner image URL.
    pub banner_url: Option<String>,
    /// Community display name.
    pub display_name: Option<String>,
    /// Community logo image URL.
    pub logo_url: Option<String>,
    /// Community URL name.
    pub name: Option<String>,
}

/// Preview group display context.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ContextGroup {
    /// Group banner image URL.
    pub banner_url: Option<String>,
    /// Group logo image URL.
    pub logo_url: Option<String>,
    /// Group display name.
    pub name: Option<String>,
    /// Group URL slug.
    pub slug: Option<String>,
}

/// Preview person display context.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ContextPerson {
    /// Person company.
    pub company: Option<String>,
    /// Whether the speaker is featured.
    pub featured: Option<bool>,
    /// Person display name.
    pub name: Option<String>,
    /// Person profile image URL.
    pub photo_url: Option<String>,
    /// Person title.
    pub title: Option<String>,
    /// Person username.
    pub username: Option<String>,
}

impl ContextPerson {
    /// Returns the display name for the person.
    pub(crate) fn display_name(&self) -> String {
        first_text([self.name.as_deref(), self.username.as_deref()])
            .unwrap_or_else(|| "Unnamed person".to_string())
    }

    /// Returns the best subtitle for the person.
    pub(crate) fn subtitle(&self) -> Option<String> {
        match (
            normalize_text(self.title.clone()),
            normalize_text(self.company.clone()),
        ) {
            (Some(title), Some(company)) => Some(format!("{title}, {company}")),
            (Some(title), None) => Some(title),
            (None, Some(company)) => Some(company),
            (None, None) => None,
        }
    }
}

/// Preview-only session display context.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ContextSession {
    /// Session type display label.
    pub kind_label: Option<String>,
    /// Session name.
    pub name: Option<String>,
    /// Session speakers with display data.
    #[serde(default)]
    pub speakers: Vec<ContextPerson>,
}

/// Preview sponsor display context.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ContextSponsor {
    /// Sponsor level for this event.
    pub level: Option<String>,
    /// Sponsor logo URL.
    pub logo_url: Option<String>,
    /// Sponsor name.
    pub name: Option<String>,
    /// Sponsor website URL.
    pub website_url: Option<String>,
}

impl ContextSponsor {
    /// Returns the display label for the sponsor level.
    pub(crate) fn level_label(&self) -> String {
        normalize_text(self.level.clone()).unwrap_or_else(|| "Sponsor".to_string())
    }

    /// Returns the sponsor display name.
    pub(crate) fn name_label(&self) -> String {
        normalize_text(self.name.clone()).unwrap_or_else(|| "Unnamed sponsor".to_string())
    }
}

// Helpers.

/// Builds a display-friendly location string from submitted venue fields.
fn build_location(input: &Input) -> Option<String> {
    // Normalize location parts supplied by the editor
    let country = normalize_text(input.venue_country_name.clone())
        .or_else(|| normalize_text(input.venue_country_code.clone()));
    let parts = [
        input.venue_name.clone(),
        input.venue_address.clone(),
        input.venue_city.clone(),
        input.venue_state.clone(),
        country,
        input.venue_zip_code.clone(),
    ];
    let normalized: Vec<_> = parts.into_iter().filter_map(normalize_text).collect();

    // Join only the details that have visible content
    if normalized.is_empty() {
        None
    } else {
        Some(normalized.join(", "))
    }
}

/// Builds the missing-fields summary shown in the preview.
fn build_missing_fields(input: &Input, context: &Context, venue_label: Option<&str>) -> Vec<String> {
    let mut missing = Vec::new();

    // Check core publishing and display fields
    if normalize_text(input.name.clone()).is_none() {
        missing.push("Event name".to_string());
    }
    if first_text([context.kind_label.as_deref(), input.kind_id.as_deref()]).is_none() {
        missing.push("Event type".to_string());
    }
    if first_text([context.category_label.as_deref(), input.category_id.as_deref()]).is_none() {
        missing.push("Category".to_string());
    }
    if normalize_text(input.timezone.clone()).is_none() {
        missing.push("Timezone".to_string());
    }
    if normalize_text(input.starts_at.clone()).is_none() {
        missing.push("Start date".to_string());
    }
    if normalize_text(input.description.clone()).is_none() {
        missing.push("Description".to_string());
    }

    // Check venue details for in-person or hybrid events
    match normalize_text(input.kind_id.clone()).as_deref() {
        Some("in-person" | "hybrid") if venue_label.is_none() => missing.push("Venue details".to_string()),
        _ => {}
    }

    // Check meeting details for virtual or hybrid events
    match normalize_text(input.kind_id.clone()).as_deref() {
        Some("virtual" | "hybrid")
            if normalize_text(input.meeting_join_url.clone()).is_none()
                && !option_truthy(input.meeting_requested.as_deref()) =>
        {
            missing.push("Online meeting details".to_string());
        }
        _ => {}
    }

    // Check call-for-speakers fields only when enabled
    if option_truthy(input.cfs_enabled.as_deref()) {
        if normalize_text(input.cfs_starts_at.clone()).is_none() {
            missing.push("CFS open date".to_string());
        }
        if normalize_text(input.cfs_ends_at.clone()).is_none() {
            missing.push("CFS close date".to_string());
        }
        if normalize_text(input.cfs_description.clone()).is_none() {
            missing.push("CFS description".to_string());
        }
    }

    missing
}

/// Builds a display label for a session's online details.
fn build_session_online_label(input: &InputSession) -> Option<String> {
    if normalize_text(input.meeting_join_url.clone()).is_some() {
        Some("Meeting link provided".to_string())
    } else if option_truthy(input.meeting_requested.as_deref()) {
        Some("Automatic meeting requested".to_string())
    } else {
        None
    }
}

/// Builds preview sessions from editor payload and display context.
fn build_sessions(
    input_sessions: Option<&[InputSession]>,
    context_sessions: &[ContextSession],
    timezone: Option<&str>,
) -> Vec<Session> {
    // Align submitted sessions with display-only context by index
    let empty_sessions = [];
    let input_sessions = input_sessions.unwrap_or(&empty_sessions);
    let session_count = input_sessions.len().max(context_sessions.len());

    // Build only rows with visible content
    (0..session_count)
        .filter_map(|index| {
            let input = input_sessions.get(index).cloned().unwrap_or_default();
            let context = context_sessions.get(index).cloned().unwrap_or_default();

            if !session_has_content(&input, &context) {
                return None;
            }

            let kind_label = first_text([context.kind_label.as_deref(), input.kind.as_deref()]);
            let online_label = build_session_online_label(&input);

            Some(Session {
                date_label: session_date_label(input.starts_at.as_deref()),
                description: normalize_text(input.description),
                kind_label,
                location: normalize_text(input.location),
                name: first_text([input.name.as_deref(), context.name.as_deref()]),
                online_label,
                speakers: context.speakers,
                time_label: session_time_label(
                    input.starts_at.as_deref(),
                    input.ends_at.as_deref(),
                    timezone,
                ),
            })
        })
        .collect()
}

/// Returns the first non-empty string in the provided collection.
fn first_text<I, T>(values: I) -> Option<String>
where
    I: IntoIterator<Item = Option<T>>,
    T: AsRef<str>,
{
    values.into_iter().find_map(normalize_text)
}

/// Normalizes optional text by trimming whitespace and dropping empty strings.
fn normalize_text<T: AsRef<str>>(value: Option<T>) -> Option<String> {
    let trimmed = value?.as_ref().trim().to_string();
    if trimmed.is_empty() { None } else { Some(trimmed) }
}

/// Returns true when a submitted option-style value means enabled.
fn option_truthy(value: Option<&str>) -> bool {
    matches!(value.map(str::trim), Some("true" | "1" | "on" | "yes"))
}

/// Parses a preview datetime submitted by the dashboard editor.
fn parse_datetime(value: Option<&str>) -> Option<NaiveDateTime> {
    // Normalize the browser datetime-local value
    let value = value?.trim();
    if value.is_empty() {
        return None;
    }

    // Accept values with or without seconds
    NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M:%S")
        .or_else(|_| NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M"))
        .ok()
}

/// Formats a date label for preview datetime strings.
fn session_date_label(value: Option<&str>) -> String {
    parse_datetime(value).map_or_else(
        || "Missing start date".to_string(),
        |date| date.format("%B %-e, %Y").to_string(),
    )
}

/// Returns true when a submitted session should be rendered.
fn session_has_content(input: &InputSession, context: &ContextSession) -> bool {
    // Check submitted and display-only session fields
    first_text([
        input.name.as_deref(),
        input.description.as_deref(),
        input.kind.as_deref(),
        input.starts_at.as_deref(),
        input.ends_at.as_deref(),
        input.location.as_deref(),
        context.name.as_deref(),
        context.kind_label.as_deref(),
    ])
    .is_some()
        || !context.speakers.is_empty()
        || input.speakers.as_ref().is_some_and(|speakers| !speakers.is_empty())
}

/// Formats a time label for preview datetime strings.
fn session_time_label(starts_at: Option<&str>, ends_at: Option<&str>, timezone: Option<&str>) -> String {
    // Parse submitted session bounds and optional timezone
    let starts_at = parse_datetime(starts_at);
    let ends_at = parse_datetime(ends_at);
    let timezone = timezone
        .and_then(|value| normalize_text(Some(value)))
        .unwrap_or_default();

    // Format same-day, cross-day, and open-ended sessions
    match (starts_at, ends_at) {
        (Some(starts_at), Some(ends_at)) if starts_at.date() == ends_at.date() => {
            format!(
                "{} - {} {}",
                starts_at.format("%-I:%M %p"),
                ends_at.format("%-I:%M %p"),
                timezone
            )
        }
        (Some(starts_at), Some(ends_at)) => {
            format!(
                "{} - {} {}",
                starts_at.format("%b %-e, %-I:%M %p"),
                ends_at.format("%b %-e, %-I:%M %p"),
                timezone
            )
        }
        (Some(starts_at), None) => format!("{} {}", starts_at.format("%-I:%M %p"), timezone),
        (None, _) => "Missing start time".to_string(),
    }
}
