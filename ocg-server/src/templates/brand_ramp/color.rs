//! Color math for the brand ramp solver.
//!
//! It parses hex colors, converts between sRGB, Oklab and OKLCH (Björn
//! Ottosson's matrices), measures WCAG 2 contrast and maps out-of-gamut
//! colors back into sRGB by reducing chroma at fixed lightness and hue.

#[cfg(test)]
mod tests;

/// Bisection iterations used by the search for the highest chroma in gamut.
const BISECTION_STEPS: u32 = 40;

/// Tolerance for linear and gamma-encoded channels just outside the unit
/// range because of floating point noise.
const GAMUT_EPSILON: f64 = 1e-9;

/// Color in OKLCH coordinates.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) struct Oklch {
    /// Chroma, from 0 upward.
    pub c: f64,
    /// Hue angle in degrees, from 0 to 360.
    pub h: f64,
    /// Perceptual lightness, from 0 to 1.
    pub l: f64,
}

impl Oklch {
    /// Returns the sRGB color, which may be out of gamut.
    pub(super) fn to_srgb(self) -> Srgb {
        // Convert the polar coordinates to Oklab
        let (sin, cos) = self.h.to_radians().sin_cos();
        let (lab_a, lab_b) = (self.c * cos, self.c * sin);

        // Convert Oklab to the LMS cone space
        let lms = [
            (self.l + 0.396_337_777_4 * lab_a + 0.215_803_757_3 * lab_b).powi(3),
            (self.l - 0.105_561_345_8 * lab_a - 0.063_854_172_8 * lab_b).powi(3),
            (self.l - 0.089_484_177_5 * lab_a - 1.291_485_548_0 * lab_b).powi(3),
        ];

        // Convert LMS to linear sRGB and apply the transfer function
        Srgb {
            b: encode(
                -0.004_196_086_3 * lms[0] - 0.703_418_614_7 * lms[1] + 1.707_614_701_0 * lms[2],
            ),
            g: encode(
                -1.268_438_004_6 * lms[0] + 2.609_757_401_1 * lms[1] - 0.341_319_396_5 * lms[2],
            ),
            r: encode(
                4.076_741_662_1 * lms[0] - 3.307_711_591_3 * lms[1] + 0.230_969_929_2 * lms[2],
            ),
        }
    }

    /// Returns the color in sRGB gamut, reducing chroma at fixed lightness and
    /// hue when needed.
    pub(super) fn to_srgb_in_gamut(self) -> Srgb {
        // Keep colors already in gamut, and use grey at the lightness extremes
        let srgb = self.to_srgb();
        if srgb.in_gamut() {
            return srgb;
        }
        if self.l <= 0.0 || self.l >= 1.0 {
            return Self { c: 0.0, ..self }.to_srgb().clamped();
        }

        // Find the highest chroma in gamut by bisection
        let (mut low, mut high) = (0.0, self.c);
        for _ in 0..BISECTION_STEPS {
            let mid = f64::midpoint(low, high);
            if (Self { c: mid, ..self }).to_srgb().in_gamut() {
                low = mid;
            } else {
                high = mid;
            }
        }
        Self { c: low, ..self }.to_srgb().clamped()
    }
}

/// Color in sRGB with gamma-encoded channels from 0 to 1.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) struct Srgb {
    /// Blue channel.
    pub b: f64,
    /// Green channel.
    pub g: f64,
    /// Red channel.
    pub r: f64,
}

impl Srgb {
    /// Pure white.
    pub(super) const WHITE: Self = Self {
        b: 1.0,
        g: 1.0,
        r: 1.0,
    };

    /// Returns the WCAG 2 contrast ratio between two colors.
    pub(super) fn contrast(self, other: Self) -> f64 {
        let (first, second) = (self.relative_luminance(), other.relative_luminance());
        (first.max(second) + 0.05) / (first.min(second) + 0.05)
    }

    /// Returns whether every channel is within the unit range.
    pub(super) fn in_gamut(self) -> bool {
        [self.r, self.g, self.b]
            .iter()
            .all(|channel| (-GAMUT_EPSILON..=1.0 + GAMUT_EPSILON).contains(channel))
    }

    /// Parses `#rgb` or `#rrggbb` in either case.
    pub(super) fn parse_hex(value: &str) -> Option<Self> {
        // Read every digit, rejecting anything but hex digits after the hash
        let digits = value
            .strip_prefix('#')?
            .chars()
            .map(|ch| ch.to_digit(16))
            .collect::<Option<Vec<u32>>>()?;

        // Combine the digits into the three channels
        let channels: Vec<u32> = match digits.len() {
            3 => digits.iter().map(|digit| digit * 17).collect(),
            6 => digits.chunks(2).map(|pair| pair[0] * 16 + pair[1]).collect(),
            _ => return None,
        };
        let channel = |index: usize| f64::from(channels[index]) / 255.0;

        Some(Self {
            b: channel(2),
            g: channel(1),
            r: channel(0),
        })
    }

    /// Returns the WCAG 2 relative luminance.
    pub(super) fn relative_luminance(self) -> f64 {
        0.2126 * decode(self.r) + 0.7152 * decode(self.g) + 0.0722 * decode(self.b)
    }

    /// Returns the color rounded to 8 bits per channel.
    pub(super) fn rounded(self) -> Self {
        let round = |channel: f64| f64::from(to_byte(channel)) / 255.0;
        Self {
            b: round(self.b),
            g: round(self.g),
            r: round(self.r),
        }
    }

    /// Returns the color as lowercase `#rrggbb`, rounded to 8 bits.
    pub(super) fn to_hex(self) -> String {
        format!(
            "#{:02x}{:02x}{:02x}",
            to_byte(self.r),
            to_byte(self.g),
            to_byte(self.b)
        )
    }

    /// Returns the color in OKLCH.
    pub(super) fn to_oklch(self) -> Oklch {
        // Convert linear sRGB to the LMS cone space
        let (r, g, b) = (decode(self.r), decode(self.g), decode(self.b));
        let lms = [
            (0.412_221_470_8 * r + 0.536_332_536_3 * g + 0.051_445_992_9 * b).cbrt(),
            (0.211_903_498_2 * r + 0.680_699_545_1 * g + 0.107_396_956_6 * b).cbrt(),
            (0.088_302_461_9 * r + 0.281_718_837_6 * g + 0.629_978_700_5 * b).cbrt(),
        ];

        // Convert LMS to Oklab
        let l = 0.210_454_255_3 * lms[0] + 0.793_617_785_0 * lms[1] - 0.004_072_046_8 * lms[2];
        let lab_a = 1.977_998_495_1 * lms[0] - 2.428_592_205_0 * lms[1] + 0.450_593_709_9 * lms[2];
        let lab_b = 0.025_904_037_1 * lms[0] + 0.782_771_766_2 * lms[1] - 0.808_675_766_0 * lms[2];

        // Convert Oklab to polar coordinates
        Oklch {
            c: lab_a.hypot(lab_b),
            h: lab_b.atan2(lab_a).to_degrees().rem_euclid(360.0),
            l,
        }
    }

    /// Returns the color with every channel clamped to the unit range.
    fn clamped(self) -> Self {
        Self {
            b: self.b.clamp(0.0, 1.0),
            g: self.g.clamp(0.0, 1.0),
            r: self.r.clamp(0.0, 1.0),
        }
    }
}

/// Converts a gamma-encoded sRGB channel to linear light.
fn decode(channel: f64) -> f64 {
    if channel <= 0.040_45 {
        channel / 12.92
    } else {
        ((channel + 0.055) / 1.055).powf(2.4)
    }
}

/// Converts a linear-light channel to gamma-encoded sRGB, keeping its sign.
fn encode(channel: f64) -> f64 {
    if channel.abs() <= 0.003_130_8 {
        channel * 12.92
    } else {
        channel.signum() * (1.055 * channel.abs().powf(1.0 / 2.4) - 0.055)
    }
}

/// Converts a gamma-encoded channel to its nearest 8-bit value.
#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn to_byte(channel: f64) -> u8 {
    // The clamp keeps the rounded value within 0..=255
    (channel.clamp(0.0, 1.0) * 255.0).round() as u8
}
