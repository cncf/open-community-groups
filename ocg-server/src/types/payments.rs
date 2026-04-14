//! Payments-related types.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

/// Discount type supported by ticketed events.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventDiscountType {
    #[default]
    FixedAmount,
    Percentage,
}

/// Status of a purchase recorded by the platform.
#[derive(
    Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum EventPurchaseStatus {
    Completed,
    Expired,
    #[default]
    Pending,
    RefundPending,
    RefundRequested,
    Refunded,
}

/// Status of an attendee refund request.
#[derive(
    Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum EventRefundRequestStatus {
    Approved,
    Approving,
    #[default]
    Pending,
    Rejected,
}

/// Mode used by a payments provider.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PaymentMode {
    Live,
    Test,
}

/// Supported payments providers.
#[derive(
    Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "snake_case")]
#[strum(serialize_all = "snake_case")]
pub enum PaymentProvider {
    #[default]
    Stripe,
}

/// Discount code configuration for a ticketed event.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct EventDiscountCode {
    /// Whether the code is currently enabled.
    pub active: bool,
    /// Discount code entered by attendees.
    pub code: String,
    /// Unique identifier for the discount code.
    pub event_discount_code_id: Uuid,
    /// Type of discount to apply.
    pub kind: EventDiscountType,
    /// Display title shown in the dashboard.
    pub title: String,

    /// Number of redemptions still available.
    pub available: Option<i32>,
    /// Fixed amount discount in minor units.
    pub amount_minor: Option<i64>,
    /// Last date and time when the code can be used.
    #[serde(default)]
    pub ends_at: Option<DateTime<Utc>>,
    /// Percentage discount to apply.
    pub percentage: Option<i32>,
    /// First date and time when the code can be used.
    #[serde(default)]
    pub starts_at: Option<DateTime<Utc>>,
    /// Maximum number of redemptions allowed.
    pub total_available: Option<i32>,
}

/// Purchase summary shown to organizers and attendees.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct EventPurchaseSummary {
    /// Discount amount applied to the purchase.
    pub discount_amount_minor: i64,
    /// Recorded purchase amount after discounts.
    pub amount_minor: i64,
    /// Currency used for the purchase.
    pub currency_code: String,
    /// Purchase identifier.
    pub event_purchase_id: Uuid,
    /// Purchase status.
    pub status: EventPurchaseStatus,
    /// Ticket type identifier.
    pub event_ticket_type_id: Uuid,
    /// Ticket type title snapshot.
    pub ticket_title: String,

    /// Discount code used for the purchase.
    pub discount_code: Option<String>,
    /// Time when the purchase was completed.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub completed_at: Option<DateTime<Utc>>,
    /// Time when the payment hold expires.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub hold_expires_at: Option<DateTime<Utc>>,
    /// Provider checkout URL for resuming the payment.
    pub provider_checkout_url: Option<String>,
    /// Provider payment reference used to manage the completed payment.
    pub provider_payment_reference: Option<String>,
    /// Provider purchase session identifier.
    pub provider_session_id: Option<String>,
    /// When the purchase was refunded.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub refunded_at: Option<DateTime<Utc>>,
}

/// Current attendee-facing ticket purchase information.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct EventTicketCurrentPrice {
    /// Final price in minor units.
    pub amount_minor: i64,

    /// Window end date and time.
    #[serde(default)]
    pub ends_at: Option<DateTime<Utc>>,
    /// Window start date and time.
    #[serde(default)]
    pub starts_at: Option<DateTime<Utc>>,
}

/// Ticket price window configuration.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct EventTicketPriceWindow {
    /// Price in minor units.
    pub amount_minor: i64,
    /// Unique identifier for the price window.
    pub event_ticket_price_window_id: Uuid,

    /// Window end date and time.
    #[serde(default)]
    pub ends_at: Option<DateTime<Utc>>,
    /// Window start date and time.
    #[serde(default)]
    pub starts_at: Option<DateTime<Utc>>,
}

impl EventTicketPriceWindow {
    /// Check if the window is currently active.
    pub fn is_active_now(&self) -> bool {
        let now = Utc::now();

        if let Some(starts_at) = self.starts_at
            && now < starts_at
        {
            return false;
        }

        if let Some(ends_at) = self.ends_at
            && now > ends_at
        {
            return false;
        }

        true
    }
}

/// Ticket type configuration stored on an event.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct EventTicketType {
    /// Whether the ticket type can currently be selected.
    pub active: bool,
    /// Unique identifier for the ticket type.
    pub event_ticket_type_id: Uuid,
    /// Display order in event pages and forms.
    pub order: i32,
    /// Ticket type display name.
    pub title: String,

    /// Current attendee-facing price and availability.
    pub current_price: Option<EventTicketCurrentPrice>,
    /// Optional subtitle shown in forms and event pages.
    pub description: Option<String>,
    /// Number of seats still available.
    pub remaining_seats: Option<i32>,
    /// Price windows configured for this ticket type.
    #[serde(default)]
    pub price_windows: Vec<EventTicketPriceWindow>,
    /// Whether this ticket type is sold out.
    #[serde(default)]
    pub sold_out: bool,
    /// Total seats available for this ticket type.
    pub seats_total: Option<i32>,
}

impl EventTicketType {
    /// Return the attendee-facing price that applies right now.
    pub fn current_amount_minor(&self) -> Option<i64> {
        self.current_price
            .as_ref()
            .map(|price| price.amount_minor)
            .or_else(|| {
                self.price_windows
                    .iter()
                    .find(|window| window.is_active_now())
                    .map(|window| window.amount_minor)
            })
    }

    /// Returns the attendee-facing current price formatted for display.
    pub fn formatted_current_price(&self, currency_code: &str) -> Option<String> {
        let amount_minor = self.current_amount_minor()?;

        if amount_minor == 0 {
            return Some("Free".to_string());
        }

        Some(format_amount_minor(amount_minor, currency_code))
    }

    /// Returns true when attendees can currently select this ticket type.
    pub fn is_sellable_now(&self) -> bool {
        self.active && !self.sold_out && self.current_amount_minor().is_some()
    }
}

/// Group-level payout recipient details.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct GroupPaymentRecipient {
    /// Provider used for payouts.
    pub provider: PaymentProvider,
    /// Provider recipient identifier.
    pub recipient_id: String,
}

/// Checkout data returned after preparing an attendee purchase.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct PreparedEventCheckout {
    /// Community slug used in attendee-facing routes.
    pub community_name: String,
    /// Event identifier.
    pub event_id: Uuid,
    /// Event slug used in attendee-facing routes.
    pub event_slug: String,
    /// Group slug used in attendee-facing routes.
    pub group_slug: String,
    /// Prepared purchase summary for the attendee.
    #[serde(flatten)]
    pub purchase: EventPurchaseSummary,
    /// Recipient account configured for the event's group.
    pub recipient: GroupPaymentRecipient,
}

// Helpers.

/// Formats a price in minor units using a currency code.
pub(crate) fn format_amount_minor(amount_minor: i64, currency_code: &str) -> String {
    let normalized_currency_code = normalized_currency_code(currency_code);

    if uses_zero_decimal_minor_units(normalized_currency_code.as_str()) {
        // These currencies do not expose a fractional component when displayed
        return format!("{normalized_currency_code} {amount_minor}");
    }

    let whole = amount_minor / 100;
    let fraction = (amount_minor % 100).abs();

    // Use the absolute remainder so negative values keep a positive fraction
    format!("{normalized_currency_code} {whole}.{fraction:02}")
}

// Normalize user and database currency inputs before display formatting
fn normalized_currency_code(currency_code: &str) -> String {
    currency_code.trim().to_ascii_uppercase()
}

// Detect currencies whose displayed amount does not include fractional units
fn uses_zero_decimal_minor_units(currency_code: &str) -> bool {
    ZERO_DECIMAL_CURRENCY_CODES.contains(&currency_code)
}

// ISO currency codes that are displayed without a fractional component
const ZERO_DECIMAL_CURRENCY_CODES: [&str; 16] = [
    "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF",
    "XPF",
];

#[cfg(test)]
mod tests {
    use super::format_amount_minor;

    #[test]
    fn format_amount_minor_formats_two_decimal_currencies() {
        assert_eq!(format_amount_minor(2_500, "usd"), "USD 25.00");
    }

    #[test]
    fn format_amount_minor_formats_zero_decimal_currencies() {
        assert_eq!(format_amount_minor(5_000, "jpy"), "JPY 5000");
    }

    #[test]
    fn format_amount_minor_normalizes_currency_codes() {
        assert_eq!(format_amount_minor(2_500, " usd "), "USD 25.00");
    }

    #[test]
    fn format_amount_minor_preserves_negative_amounts() {
        assert_eq!(format_amount_minor(-250, "usd"), "USD -2.50");
    }
}
