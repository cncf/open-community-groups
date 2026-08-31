//! Payments-related types.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use sha2::{Digest, Sha256};
use uuid::Uuid;

/// ISO currency codes displayed without fractional units.
const ZERO_DECIMAL_CURRENCY_CODES: [&str; 16] = [
    "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV",
    "XAF", "XOF", "XPF",
];

/// Discount type supported by event admission tiers.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventDiscountType {
    /// Fixed discount in minor currency units.
    #[default]
    FixedAmount,
    /// Percentage discount.
    Percentage,
}

/// Charge model recorded on an event purchase.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize, strum::EnumString)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum EventPurchaseChargeModel {
    /// Paid purchase collected through a connected-account direct charge.
    DirectCharge,
    /// Paid purchase collected outside the platform.
    External,
    /// Free purchase completed inside OCG.
    #[default]
    OcgFree,
}

impl EventPurchaseChargeModel {
    /// Returns whether the purchase is collected outside the platform.
    pub fn is_external(self) -> bool {
        matches!(self, Self::External)
    }
}

/// Status of a purchase recorded by the platform.
#[derive(
    Clone,
    Copy,
    Debug,
    Default,
    Eq,
    PartialEq,
    Serialize,
    Deserialize,
    strum::Display,
    strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum EventPurchaseStatus {
    /// Purchase completed successfully.
    Completed,
    /// Pending purchase expired.
    Expired,
    /// Purchase awaits checkout completion.
    #[default]
    Pending,
    /// Purchase was refunded.
    Refunded,
    /// Provider refund is still pending.
    RefundPending,
    /// A locally finalized refund is being recovered after provider failure.
    RefundRecoveryPending,
    /// Attendee requested a refund.
    RefundRequested,
}

/// Attendee-facing progress for a durable purchase refund.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum EventRefundProgress {
    /// Checkout has not completed, so no provider refund can start yet.
    AwaitingCheckout,
    /// A worker or the payments provider is processing the refund.
    Processing,
    /// Durable refund work is waiting for a worker or retry delay.
    Queued,
    /// The provider failure requires external operator recovery.
    RecoveryRequired,
    /// Provider and local refund work completed.
    Refunded,
    /// Automatic attempts were exhausted and an administrator can retry.
    RetryableFailure,
}

/// Status of an attendee refund request.
#[derive(
    Clone,
    Copy,
    Debug,
    Default,
    Eq,
    PartialEq,
    Serialize,
    Deserialize,
    strum::Display,
    strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum EventRefundRequestStatus {
    /// Refund request was approved.
    Approved,
    /// Refund request is being approved with the provider.
    Approving,
    /// Refund request awaits organizer review.
    #[default]
    Pending,
    /// Refund request was rejected.
    Rejected,
}

/// Mode used by a payments provider.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PaymentMode {
    /// Provider accepts live payments.
    Live,
    /// Provider uses test transactions.
    Test,
}

/// Supported payments providers.
#[derive(
    Clone,
    Copy,
    Debug,
    Default,
    Eq,
    PartialEq,
    Serialize,
    Deserialize,
    strum::Display,
    strum::EnumString,
)]
#[serde(rename_all = "snake_case")]
#[strum(serialize_all = "snake_case")]
pub enum PaymentProvider {
    /// Stripe payments provider.
    #[default]
    Stripe,
}

/// Discount code configuration for event admission.
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

    /// Fixed amount discount in minor units.
    pub amount_minor: Option<i64>,
    /// Number of redemptions still available.
    pub available: Option<i32>,
    /// Whether Uses remaining is currently in manual override mode.
    #[serde(default)]
    pub available_override_active: bool,
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
    /// Recorded purchase amount after discounts.
    pub amount_minor: i64,
    /// Charge model used to collect the purchase.
    #[serde(default)]
    pub charge_model: EventPurchaseChargeModel,
    /// Discount amount applied to the purchase.
    pub discount_amount_minor: i64,
    /// Purchase identifier.
    pub event_purchase_id: Uuid,
    /// Ticket type identifier.
    pub event_ticket_type_id: Uuid,
    /// Provisional platform fee requested at Checkout creation, in minor units.
    pub provisional_platform_fee_amount_minor: i64,
    /// Purchase status.
    pub status: EventPurchaseStatus,
    /// Ticket type title snapshot.
    pub ticket_title: String,

    /// Time when the purchase was completed.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub completed_at: Option<DateTime<Utc>>,
    /// Currency used for the purchase.
    pub currency_code: Option<String>,
    /// Discount code used for the purchase.
    pub discount_code: Option<String>,
    /// Organizer-entered details recorded when an external payment was marked paid.
    pub external_payment_details: Option<String>,
    /// Organizer-supplied payment instructions from the event.
    pub external_payment_instructions: Option<String>,
    /// Payment URL from the event shown to the attendee.
    pub external_payment_url: Option<String>,
    /// Time when the payment hold expires.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub hold_expires_at: Option<DateTime<Utc>>,
    /// Provider checkout URL for resuming the payment.
    pub provider_checkout_url: Option<String>,
    /// Connected account that owns provider objects for direct charges.
    pub provider_object_account_id: Option<String>,
    /// Provider payment reference used to manage the completed payment.
    pub provider_payment_reference: Option<String>,
    /// Provider purchase session identifier.
    pub provider_session_id: Option<String>,
    /// Authoritative total paid to the provider, in minor units.
    pub provider_total_minor: Option<i64>,
    /// When the purchase was refunded.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub refunded_at: Option<DateTime<Utc>>,
}

/// Snapshot of an unpaid external purchase shown to attendees.
#[skip_serializing_none]
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ExternalPaymentInfo {
    /// Amount due in minor units.
    pub amount_minor: i64,
    /// Currency of the amount due.
    pub currency_code: String,
    /// Organizer-confirmation deadline.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub deadline: DateTime<Utc>,
    /// Stable payment reference used to match the external transfer.
    pub reference: Uuid,
    /// Snapshot of the external payment URL.
    pub url: String,

    /// Snapshot of organizer-supplied payment instructions.
    pub instructions: Option<String>,
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
    /// Whether the ticket type is publicly discoverable or invitation-only.
    pub availability: EventTicketTypeAvailability,
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
    /// Price windows configured for this ticket type.
    #[serde(default)]
    pub price_windows: Vec<EventTicketPriceWindow>,
    /// Number of seats still available.
    pub remaining_seats: Option<i32>,
    /// Total seats available for this ticket type.
    pub seats_total: Option<i32>,
    /// Whether this ticket type is sold out.
    #[serde(default)]
    pub sold_out: bool,
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

/// Availability of a configured event ticket type.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventTicketTypeAvailability {
    /// Ticket type is assigned only through organizer or workflow offers.
    InvitationOnly,
    /// Ticket type is visible through public enrollment.
    #[default]
    Public,
}

/// Immutable fiscal-sponsor seller snapshot used by a purchase.
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct FiscalSponsorSeller {
    /// Connected account that owns the provider objects.
    pub connected_account_id: String,
    /// Seller name displayed for operational context.
    pub display_name: String,
    /// Payments provider that owns the seller account.
    pub provider: PaymentProvider,
}

/// Group-level external-payments eligibility shown on settings and event forms.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct GroupExternalPaymentsContext {
    /// Whether the operator has configured external payments for this deployment.
    pub configured: bool,
    /// Whether the group's country is currently allowlisted.
    pub eligible: bool,
    /// Whether the group has opted into external payments.
    pub enabled: bool,

    /// Group country code used for allowlist matching.
    pub country_code: Option<String>,
    /// Default organizer-confirmation window in hours.
    pub default_payment_window_hours: Option<i32>,
    /// Maximum organizer-confirmation window in hours.
    pub max_payment_window_hours: Option<i32>,
}

/// Group-level payout recipient details.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct GroupPaymentRecipient {
    /// Provider used for payouts.
    pub provider: PaymentProvider,
    /// Provider recipient identifier.
    pub recipient_id: String,
    /// Legal seller name displayed to attendees.
    pub seller_display_name: String,
}

/// Provider validation bound to the payment configuration observed before mutation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub(crate) struct PaymentConfigurationValidation {
    /// Whether the provider validation included automatic-tax readiness.
    pub require_automatic_tax: bool,

    /// Payment recipient observed before taking the database mutation lock.
    pub expected_payment_recipient: Option<GroupPaymentRecipient>,
    /// Manual Tax Rate identifiers validated for an event mutation.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub manual_tax_rate_ids: Option<Vec<String>>,
    /// Tax inclusion behavior validated for an event mutation.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tax_behavior: Option<TicketTaxBehavior>,
    /// Tax calculation mode validated for an event mutation.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tax_calculation_mode: Option<TicketTaxCalculationMode>,
    /// Payment recipient validated at the provider boundary.
    pub validated_payment_recipient: Option<GroupPaymentRecipient>,
}

/// Checkout data returned after preparing an attendee purchase.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct PreparedEventCheckout {
    /// Community display name used in invoice context.
    pub community_display_name: String,
    /// Community slug used in attendee-facing routes.
    pub community_name: String,
    /// Event identifier.
    pub event_id: Uuid,
    /// Event display name used in invoice context.
    pub event_name: String,
    /// Event slug used in attendee-facing routes.
    pub event_slug: String,
    /// Event time zone used to format invoice context.
    pub event_timezone: String,
    /// Group display name used in invoice context.
    pub group_name: String,
    /// Generated group slug used in attendee-facing routes.
    pub group_slug: String,
    /// Prepared purchase summary for the attendee.
    #[serde(flatten)]
    pub purchase: EventPurchaseSummary,

    /// Fingerprint for a reusable sponsor-scoped performance location.
    pub cached_performance_location_fingerprint: Option<String>,
    /// Fingerprint for a reusable sponsor-scoped ticket Product.
    pub cached_product_fingerprint: Option<String>,
    /// Reusable provider performance location identifier.
    pub cached_provider_tax_location_id: Option<String>,
    /// Reusable provider ticket Product identifier.
    pub cached_provider_tax_product_id: Option<String>,
    /// Event start time used in invoice context.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub event_starts_at: Option<DateTime<Utc>>,
    /// Admin-managed group slug used in attendee-facing routes.
    pub group_slug_pretty: Option<String>,
    /// Manual Tax Rate identifiers selected for the purchase.
    pub manual_tax_rate_ids: Option<Vec<String>>,
    /// Immutable connected fiscal-sponsor seller snapshot.
    pub seller: Option<FiscalSponsorSeller>,
    /// Ticket price tax inclusion behavior.
    pub tax_behavior: Option<TicketTaxBehavior>,
    /// Selected automatic or manual tax path.
    pub tax_calculation_mode: Option<TicketTaxCalculationMode>,
    /// Professional-event tax code used for automatic tax.
    pub tax_code: Option<String>,
    /// Immutable physical venue used for tax calculation.
    pub venue: Option<TicketVenue>,
}

/// Tax inclusion behavior selected for an event ticket.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TicketTaxBehavior {
    /// Tax is added to the configured ticket price.
    Exclusive,
    /// Tax is included in the configured ticket price.
    #[default]
    Inclusive,
}

/// Tax calculation path selected for an event ticket.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TicketTaxCalculationMode {
    /// Stripe Tax calculates tax from the performance location.
    #[default]
    Automatic,
    /// Stripe applies the event's selected manual Tax Rates.
    Manual,
    /// Checkout does not attach any tax calculation mechanism.
    None,
}

impl TicketTaxCalculationMode {
    /// Returns whether Checkout attaches an event tax mechanism.
    pub const fn collects_tax(self) -> bool {
        !matches!(self, Self::None)
    }
}

/// Normalized event jurisdiction used for ticket-tax readiness checks.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct TicketTaxJurisdiction {
    /// ISO country code of the event venue.
    pub country_code: String,

    /// ISO state or province code of the event venue.
    pub state_code: Option<String>,
}

impl TicketTaxJurisdiction {
    /// Formats the jurisdiction for organizer-facing readiness errors.
    pub(crate) fn display_code(&self) -> String {
        self.state_code.as_ref().map_or_else(
            || self.country_code.clone(),
            |state_code| format!("{}-{state_code}", self.country_code),
        )
    }
}

/// Active Stripe Tax Rate available in a fiscal sponsor account.
#[skip_serializing_none]
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub(crate) struct TicketTaxRate {
    /// Customer-facing Tax Rate label.
    pub display_name: String,
    /// Connected-account Stripe Tax Rate identifier.
    pub id: String,
    /// Whether the rate is included in the configured ticket amount.
    pub inclusive: bool,
    /// Decimal Tax Rate percentage encoded without floating-point conversion.
    pub percentage: String,

    /// Jurisdiction configured on the Tax Rate.
    pub jurisdiction: Option<String>,
}

/// Immutable physical venue snapshot used for ticket tax.
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct TicketVenue {
    /// Street address of the venue.
    pub address: String,
    /// City containing the venue.
    pub city: String,
    /// ISO country code of the venue.
    pub country_code: String,
    /// Venue display name.
    pub name: String,
    /// Postal code of the venue.
    pub zip_code: String,

    /// ISO state or province code containing the venue.
    pub state_code: Option<String>,
    /// Full state or province name containing the venue.
    pub state_name: Option<String>,
}

/// Required field in a physical ticket venue.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum TicketVenueField {
    /// Street address field.
    Address,
    /// City field.
    City,
    /// ISO country code field.
    CountryCode,
    /// Venue display name field.
    Name,
    /// Postal code field.
    ZipCode,
}

impl TicketVenue {
    /// Returns whether the country code has a valid ISO code shape.
    pub(crate) fn has_valid_country_code(&self) -> bool {
        self.country_code.len() == 2
            && self
                .country_code
                .chars()
                .all(|character| character.is_ascii_alphabetic())
    }

    /// Returns the required venue fields whose values are blank.
    pub(crate) fn missing_required_fields(&self) -> Vec<TicketVenueField> {
        [
            (TicketVenueField::Address, self.address.as_str()),
            (TicketVenueField::City, self.city.as_str()),
            (TicketVenueField::CountryCode, self.country_code.as_str()),
            (TicketVenueField::Name, self.name.as_str()),
            (TicketVenueField::ZipCode, self.zip_code.as_str()),
        ]
        .into_iter()
        .filter_map(|(field, value)| value.trim().is_empty().then_some(field))
        .collect()
    }

    /// Normalizes address codes and optional strings before provider use and caching.
    pub(crate) fn normalized(&self) -> Self {
        Self {
            address: self.address.trim().to_string(),
            city: self.city.trim().to_string(),
            country_code: self.country_code.trim().to_ascii_uppercase(),
            name: self.name.trim().to_string(),
            zip_code: self.zip_code.trim().to_string(),

            state_code: self
                .state_code
                .as_deref()
                .map(str::trim)
                .filter(|state_code| !state_code.is_empty())
                .map(str::to_ascii_uppercase),
            state_name: self
                .state_name
                .as_deref()
                .map(str::trim)
                .filter(|state_name| !state_name.is_empty())
                .map(str::to_string),
        }
    }

    /// Builds the venue fingerprint shared by Rust and `PostgreSQL`.
    pub(crate) fn performance_location_fingerprint(&self) -> String {
        // Collect fields in the exact order used by PostgreSQL
        let parts = [
            self.address.as_str(),
            self.city.as_str(),
            self.country_code.as_str(),
            self.name.as_str(),
            self.state_code.as_deref().unwrap_or_default(),
            self.zip_code.as_str(),
        ];
        let mut digest = Sha256::new();

        // Separate fields so adjacent values cannot produce an ambiguous fingerprint
        for part in parts {
            digest.update(part.as_bytes());
            digest.update([0]);
        }

        hex::encode(digest.finalize())
    }

    /// Returns the normalized country and subdivision used for tax readiness.
    pub(crate) fn tax_jurisdiction(&self) -> TicketTaxJurisdiction {
        let venue = self.normalized();

        TicketTaxJurisdiction {
            country_code: venue.country_code,
            state_code: venue.state_code,
        }
    }

    /// Returns a normalized tax jurisdiction when the venue country is valid.
    pub(crate) fn valid_tax_jurisdiction(&self) -> Option<TicketTaxJurisdiction> {
        let venue = self.normalized();

        venue.has_valid_country_code().then_some(TicketTaxJurisdiction {
            country_code: venue.country_code,
            state_code: venue.state_code,
        })
    }
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

/// Normalizes user and database currency inputs before display formatting.
fn normalized_currency_code(currency_code: &str) -> String {
    currency_code.trim().to_ascii_uppercase()
}

/// Returns whether a currency is displayed without fractional units.
fn uses_zero_decimal_minor_units(currency_code: &str) -> bool {
    ZERO_DECIMAL_CURRENCY_CODES.contains(&currency_code)
}

#[cfg(test)]
mod tests {
    use super::{TicketVenue, TicketVenueField, format_amount_minor};

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

    #[test]
    fn test_ticket_venue_country_code_validation_checks_iso_shape() {
        // Setup a valid two-letter country code
        let mut venue = TicketVenue {
            country_code: "PT".to_string(),
            ..TicketVenue::default()
        };

        // Check valid, long, and non-alphabetic country codes
        assert!(venue.has_valid_country_code());

        venue.country_code = "PRT".to_string();
        assert!(!venue.has_valid_country_code());

        venue.country_code = "P1".to_string();
        assert!(!venue.has_valid_country_code());
    }

    #[test]
    fn test_ticket_venue_fingerprint_treats_missing_state_as_empty() {
        // Setup equivalent venues with absent and empty state codes
        let venue = TicketVenue {
            address: "1 Main St".to_string(),
            city: "Portland".to_string(),
            country_code: "US".to_string(),
            name: "Venue".to_string(),
            zip_code: "97201".to_string(),

            state_code: None,
            state_name: None,
        };
        let venue_with_empty_state = TicketVenue {
            state_code: Some(String::new()),
            ..venue.clone()
        };

        // Check the digest matches the shared PostgreSQL algorithm
        assert_eq!(
            venue.performance_location_fingerprint(),
            "b5b9cb58e4b43c71a197fbcd6eefc5bf7e609c48b78a3272858b25f170d62d35"
        );
        assert_eq!(
            venue.performance_location_fingerprint(),
            venue_with_empty_state.performance_location_fingerprint()
        );
    }

    #[test]
    fn test_ticket_venue_missing_required_fields_reports_blank_values() {
        // Setup a venue with blank and populated required fields
        let venue = TicketVenue {
            address: " ".to_string(),
            city: "Portland".to_string(),
            country_code: String::new(),
            name: "\t".to_string(),
            zip_code: "97201".to_string(),

            state_code: None,
            state_name: None,
        };

        // Check only blank fields are reported in venue field order
        assert_eq!(
            venue.missing_required_fields(),
            [
                TicketVenueField::Address,
                TicketVenueField::CountryCode,
                TicketVenueField::Name,
            ]
        );
    }

    #[test]
    fn test_ticket_venue_normalized_cleans_address_values() {
        // Setup a venue with whitespace and lowercase location codes
        let venue = TicketVenue {
            address: " 1 Main St ".to_string(),
            city: " Portland ".to_string(),
            country_code: " us ".to_string(),
            name: " Venue ".to_string(),
            zip_code: " 97201 ".to_string(),

            state_code: Some(" or ".to_string()),
            state_name: Some(" Oregon ".to_string()),
        };

        // Check required and optional location values are normalized
        assert_eq!(
            venue.normalized(),
            TicketVenue {
                address: "1 Main St".to_string(),
                city: "Portland".to_string(),
                country_code: "US".to_string(),
                name: "Venue".to_string(),
                zip_code: "97201".to_string(),

                state_code: Some("OR".to_string()),
                state_name: Some("Oregon".to_string()),
            }
        );
    }

    #[test]
    fn test_ticket_venue_normalized_omits_blank_optional_values() {
        // Setup optional location fields containing only whitespace
        let venue = TicketVenue {
            state_code: Some(" ".to_string()),
            state_name: Some("\t".to_string()),
            ..TicketVenue::default()
        };
        let normalized = venue.normalized();

        // Check blank optional values are represented as absent
        assert_eq!(normalized.state_code, None);
        assert_eq!(normalized.state_name, None);
    }
}
