//! Templates for the event analytics tab in the group dashboard.

use std::{cmp::Reverse, fmt::Write};

use askama::Template;
use chrono::Utc;
use num_format::{Locale, ToFormattedString};
use uuid::Uuid;

use crate::{
    templates::filters,
    types::{
        dashboard::group::event_analytics::{
            EventAdmissionOfferOutcome, EventAnalytics, EventQuestionBreakdown,
            EventTicketTypeUsage,
        },
        event::EventAdmissionOfferSource,
        questionnaire::QuestionnaireQuestionKind,
    },
};

#[cfg(test)]
mod tests;

/// Placeholder displayed when a metric does not apply.
const NOT_APPLICABLE_LABEL: &str = "-";

/// Number of options shown for each registration question until expanded.
pub(crate) const QUESTION_VISIBLE_OPTIONS: usize = 10;

/// Format used to display registration window bounds in the event timezone.
pub(crate) const WINDOW_DATE_FORMAT: &str = "%b %-d, %Y %H:%M";

// Pages templates.

/// Event analytics tab template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/event_analytics.html")]
pub(crate) struct Page {
    /// Event identifier.
    pub event_id: Uuid,
    /// Statistics to render.
    pub stats: EventAnalytics,
}

impl Page {
    /// Returns the admission offers grouped by source, with their outcomes.
    pub(crate) fn admission_offer_sources(&self) -> Vec<AdmissionOfferSourceSummary> {
        let mut summaries: Vec<(EventAdmissionOfferSource, i64, Vec<String>)> = Vec::new();
        for offer in &self.stats.enrollment.admission_offers {
            let outcome = format!(
                "{} {}",
                offer.count,
                self.offer_outcome_label(&offer.outcome)
            );

            // Extend the group of the current source, or start a new one
            if let Some((source, total, outcomes)) = summaries.last_mut()
                && *source == offer.source
            {
                *total += offer.count;
                outcomes.push(outcome);
            } else {
                summaries.push((offer.source, offer.count, vec![outcome]));
            }
        }
        summaries
            .into_iter()
            .map(|(source, total, outcomes)| AdmissionOfferSourceSummary {
                label: self.offer_source_label(&source),
                outcomes: outcomes.join(" · "),
                total,
            })
            .collect()
    }

    /// Returns the description of the attributed views card.
    pub(crate) fn attributed_views_description(&self) -> String {
        if !self.stats.traffic.attribution_consistent {
            return "From links with UTM values".to_string();
        }
        format!(
            "{} of page views, from links with UTM values",
            self.share_label(&self.stats.utm.tagged_views)
        )
    }

    /// Returns the check-in rate for display.
    pub(crate) fn check_in_rate_label(&self) -> String {
        percent_label(self.stats.check_in_rate())
    }

    /// Returns a text summary of the check-ins chart.
    pub(crate) fn check_ins_summary(&self) -> String {
        let check_ins: i64 = self.stats.check_ins.bins.iter().map(|(_, count)| count).sum();
        format!(
            "{check_ins} check-ins in {}-minute intervals, shown in the {} timezone.",
            self.stats.check_ins.bin_minutes, self.stats.event.timezone
        )
    }

    /// Returns the approximate conversion rate for display.
    pub(crate) fn conversion_rate_label(&self) -> String {
        percent_label(self.stats.conversion_rate())
    }

    /// Returns a text summary of the fill curve chart.
    pub(crate) fn fill_curve_summary(&self) -> String {
        let last_total = self
            .stats
            .traffic
            .registrations_running_total
            .last()
            .map_or(self.stats.traffic.registrations_baseline, |(_, total)| {
                *total
            });
        format!(
            "Registrations grew from {} to {last_total}{}.",
            self.stats.traffic.registrations_baseline,
            self.range_suffix()
        )
    }

    /// Returns the fill rate for display.
    pub(crate) fn fill_rate_label(&self) -> String {
        percent_label(self.stats.fill_rate())
    }

    /// Returns the registration funnel stages, with check-ins once the event ended.
    pub(crate) fn funnel_stages(&self) -> Vec<(&'static str, i64)> {
        let mut stages = vec![
            ("Page views", self.stats.traffic.views_total),
            ("Registrations", self.stats.enrollment.registrations),
        ];
        if self.has_ended() {
            stages.push(("Checked in", self.stats.enrollment.checked_in));
        }
        stages
    }

    /// Returns a text summary of the registration funnel chart.
    pub(crate) fn funnel_summary(&self) -> String {
        let stages = self
            .funnel_stages()
            .into_iter()
            .map(|(label, count)| format!("{label} {count}"))
            .collect::<Vec<_>>()
            .join(", ");
        format!("{stages}.")
    }

    /// Returns whether the event has ended.
    pub(crate) fn has_ended(&self) -> bool {
        self.stats.has_ended_at(Utc::now())
    }

    /// Returns whether a question accepts several options per respondent.
    #[allow(clippy::unused_self)]
    pub(crate) fn is_multi_select(&self, question: &EventQuestionBreakdown) -> bool {
        question.kind == QuestionnaireQuestionKind::MultiSelect
    }

    /// Returns the invitation requests by review status for display.
    pub(crate) fn invitation_requests_summary(&self) -> String {
        let requests = &self.stats.enrollment.invitation_requests;
        format!(
            "{} pending · {} accepted · {} rejected",
            requests.pending, requests.accepted, requests.rejected
        )
    }

    /// Returns the number of invitation requests.
    pub(crate) fn invitation_requests_total(&self) -> i64 {
        let requests = &self.stats.enrollment.invitation_requests;
        requests.accepted + requests.pending + requests.rejected
    }

    /// Returns the description of the members who joined during registration card.
    pub(crate) fn members_joined_description(&self) -> String {
        self.stats.audience.members_joined_in_window_registered.map_or_else(
            || "No registration window yet".to_string(),
            |registered| format!("{} of them registered", count_label(registered)),
        )
    }

    /// Returns the membership window in the event timezone, marking inferred and
    /// capped bounds.
    pub(crate) fn membership_window_label(&self) -> Option<String> {
        let audience = &self.stats.audience;
        let timezone = self.stats.event.timezone;
        let (starts_at, ends_at) = (audience.window_starts_at?, audience.window_ends_at?);
        let start_note = if audience.window_start_inferred {
            " (publication)"
        } else {
            ""
        };
        let end_note = if audience.window_end_capped {
            " (cut short)"
        } else if audience.window_end_inferred {
            " (no registration close)"
        } else {
            ""
        };
        Some(format!(
            "Registration window: {}{start_note} to {}{end_note}, {timezone}.",
            starts_at.with_timezone(&timezone).format(WINDOW_DATE_FORMAT),
            ends_at.with_timezone(&timezone).format(WINDOW_DATE_FORMAT),
        ))
    }

    /// Returns a lowercase label describing an admission offer outcome.
    #[allow(clippy::trivially_copy_pass_by_ref, clippy::unused_self)]
    pub(crate) fn offer_outcome_label(&self, outcome: &EventAdmissionOfferOutcome) -> &'static str {
        match outcome {
            EventAdmissionOfferOutcome::Active => "active",
            EventAdmissionOfferOutcome::Canceled => "canceled",
            EventAdmissionOfferOutcome::Completed => "completed",
            EventAdmissionOfferOutcome::DeadlinePassed => "expired (deadline passed)",
            EventAdmissionOfferOutcome::Declined => "declined",
            EventAdmissionOfferOutcome::Expired => "expired",
        }
    }

    /// Returns a label describing how an admission offer was created.
    #[allow(clippy::trivially_copy_pass_by_ref, clippy::unused_self)]
    pub(crate) fn offer_source_label(&self, source: &EventAdmissionOfferSource) -> &'static str {
        match source {
            EventAdmissionOfferSource::Approval => "Approved request",
            EventAdmissionOfferSource::OrganizerInvitation => "Organizer invitation",
            EventAdmissionOfferSource::Waitlist => "Waiting list",
        }
    }

    /// Returns an optional count for display, or a dash when missing.
    #[allow(clippy::ref_option, clippy::unused_self)]
    pub(crate) fn optional_count_label(&self, count: &Option<i64>) -> String {
        count.map_or_else(|| NOT_APPLICABLE_LABEL.to_string(), count_label)
    }

    /// Returns the number of question options hidden until expanded.
    #[allow(clippy::unused_self)]
    pub(crate) fn question_hidden_options_count(&self, question: &EventQuestionBreakdown) -> usize {
        question.options.len().saturating_sub(QUESTION_VISIBLE_OPTIONS)
    }

    /// Returns the options of a question by selections, most selected first,
    /// with their share of respondents.
    #[allow(clippy::cast_precision_loss, clippy::unused_self)]
    pub(crate) fn question_options(
        &self,
        question: &EventQuestionBreakdown,
    ) -> Vec<QuestionOptionShare> {
        // Order options by selections, keeping the definition order on ties
        let mut options = question.options.iter().collect::<Vec<_>>();
        options.sort_by_key(|option| Reverse(option.count));

        // Describe each option with its share of respondents
        options
            .into_iter()
            .enumerate()
            .map(|(index, option)| {
                let share = if question.respondents > 0 {
                    option.count as f64 / question.respondents as f64
                } else {
                    0.0
                };
                QuestionOptionShare {
                    count: option.count,
                    hidden: index >= QUESTION_VISIBLE_OPTIONS,
                    label: option.label.clone(),
                    share_label: percent_label(Some(share)),
                    width: bar_width(option.count, question.respondents),
                }
            })
            .collect()
    }

    /// Returns why the daily charts are unavailable for the event.
    pub(crate) fn range_unavailable_message(&self) -> &'static str {
        if !self.stats.event.published {
            "Daily charts start on the publication day, and this event is not published."
        } else if self.stats.event.published_at.is_none() {
            "Daily charts start on the publication day, which is not recorded for this event."
        } else {
            "Daily charts are not available because the event was published after it ended."
        }
    }

    /// Returns the registrations admitted by each path, skipping empty paths.
    pub(crate) fn registration_paths(&self) -> Vec<(&'static str, i64)> {
        let paths = &self.stats.enrollment.registrations_by_path;
        [
            ("Direct", paths.direct),
            ("Approved request", paths.approval),
            ("Waiting list", paths.waitlist),
            ("Organizer invitation", paths.organizer_invitation),
            ("Unknown", paths.unknown),
        ]
        .into_iter()
        .filter(|(_, count)| *count > 0)
        .collect()
    }

    /// Returns a text summary of the registration paths chart.
    pub(crate) fn registration_paths_summary(&self) -> String {
        let paths = self
            .registration_paths()
            .into_iter()
            .map(|(label, count)| format!("{label} {count}"))
            .collect::<Vec<_>>()
            .join(", ");
        format!("Registrations by path: {paths}.")
    }

    /// Returns a text summary of the daily registrations chart.
    pub(crate) fn registrations_summary(&self) -> String {
        let registrations = self
            .stats
            .traffic
            .registrations_by_ticket_type_per_day
            .iter()
            .map(|series| series_total(&series.series))
            .sum::<i64>();
        format!("{registrations} registrations{}.", self.range_suffix())
    }

    /// Returns the share of all page views represented by a view count, or
    /// unavailable when attribution is inconsistent.
    #[allow(clippy::trivially_copy_pass_by_ref)]
    pub(crate) fn share_label(&self, views: &i64) -> String {
        if !self.stats.traffic.attribution_consistent {
            return "Unavailable".to_string();
        }
        percent_label(self.stats.share_of_views(*views))
    }

    /// Returns the allocated seats of a ticket type, bounded by its seats.
    #[allow(clippy::unused_self)]
    pub(crate) fn ticket_type_progress_value(&self, ticket_type: &EventTicketTypeUsage) -> i64 {
        ticket_type.allocated.clamp(0, ticket_type.seats_total)
    }

    /// Returns the width percentage of the reserved seats bar segment.
    #[allow(clippy::unused_self)]
    pub(crate) fn ticket_type_reserved_width(&self, ticket_type: &EventTicketTypeUsage) -> String {
        bar_width(ticket_type.reserved(), ticket_type.seats_total)
    }

    /// Returns the width percentage of the sold seats bar segment.
    #[allow(clippy::unused_self)]
    pub(crate) fn ticket_type_sold_width(&self, ticket_type: &EventTicketTypeUsage) -> String {
        bar_width(ticket_type.sold, ticket_type.seats_total)
    }

    /// Returns the seat usage of a ticket type for display.
    #[allow(clippy::unused_self)]
    pub(crate) fn ticket_type_summary(&self, ticket_type: &EventTicketTypeUsage) -> String {
        format!(
            "{} sold · {} reserved · {} remaining of {}",
            ticket_type.sold,
            ticket_type.reserved(),
            ticket_type.remaining,
            ticket_type.seats_total
        )
    }

    /// Returns the description of the unattributed views card.
    pub(crate) fn unattributed_views_description(&self) -> String {
        self.stats.untagged_views().map_or_else(
            || "Recorded UTM views exceed the total page views".to_string(),
            |untagged_views| {
                format!(
                    "{} of page views, without recorded UTM values",
                    self.share_label(&untagged_views)
                )
            },
        )
    }

    /// Returns the unattributed views for display.
    pub(crate) fn unattributed_views_label(&self) -> String {
        self.stats
            .untagged_views()
            .map_or_else(|| "Unavailable".to_string(), count_label)
    }

    /// Returns a text summary of the traffic sources charts.
    pub(crate) fn utm_summary(&self) -> String {
        format!(
            "{} of {} page views have UTM attribution.",
            self.stats.utm.tagged_views, self.stats.traffic.views_total
        )
    }

    /// Returns a text summary of the daily views chart.
    pub(crate) fn views_summary(&self) -> String {
        let views = self
            .stats
            .traffic
            .views_by_source_per_day
            .iter()
            .map(|series| series_total(&series.series))
            .sum::<i64>();
        let mut summary = format!("{views} page views{}.", self.range_suffix());
        let hidden = self.stats.views_hidden_count();
        if hidden > 0 {
            let _ = write!(summary, " {hidden} views outside these days are not shown.");
        }
        summary
    }

    /// Returns the charted days description appended to chart summaries.
    fn range_suffix(&self) -> String {
        self.stats.range.as_ref().map_or_else(String::new, |range| {
            format!(", from {} to {} (UTC days)", range.start_day, range.end_day)
        })
    }
}

// Types.

/// Admission offers of one source, summarized by outcome.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct AdmissionOfferSourceSummary {
    /// Source label.
    pub label: &'static str,
    /// Offer counts by outcome, for display.
    pub outcomes: String,
    /// Offers of the source.
    pub total: i64,
}

/// Selections of one question option, with its share of respondents.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct QuestionOptionShare {
    /// Selections of the option.
    pub count: i64,
    /// Whether the option is hidden until the question is expanded.
    pub hidden: bool,
    /// Option label.
    pub label: String,
    /// Share of respondents for display.
    pub share_label: String,
    /// Width percentage of the option bar.
    pub width: String,
}

// Helpers.

/// Returns a bar segment width as a percentage of a total.
#[allow(clippy::cast_precision_loss)]
fn bar_width(value: i64, total: i64) -> String {
    if total <= 0 {
        return "0".to_string();
    }
    let width = (value as f64 / total as f64 * 100.0).clamp(0.0, 100.0);
    format!("{width:.1}")
}

/// Formats a count with thousands separators.
fn count_label(count: i64) -> String {
    count.to_formatted_string(&Locale::en)
}

/// Formats a ratio as a percentage, or as a dash when missing.
fn percent_label(value: Option<f64>) -> String {
    let Some(value) = value else {
        return NOT_APPLICABLE_LABEL.to_string();
    };
    let percent = value * 100.0;
    if percent >= 10.0 || (percent - percent.round()).abs() < f64::EPSILON {
        format!("{percent:.0}%")
    } else {
        format!("{percent:.1}%")
    }
}

/// Returns the sum of a day series.
fn series_total(series: &[(String, i64)]) -> i64 {
    series.iter().map(|(_, count)| count).sum()
}
