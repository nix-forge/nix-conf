//! Preserve persisted legacy JSON fingerprints and native numeric build labels.
use std::error::Error;
type Result<T> = std::result::Result<T, Box<dyn Error>>;

// CPython repr uses shortest round-trip digits, fixed notation for exponents
// -4 through 15, and a decimal suffix for integral floats.
pub fn python_float(number: f64) -> Result<String> {
    if !number.is_finite() {
        return Err("non-finite legacy number".into());
    }
    let sign = if number.is_sign_negative() { "-" } else { "" };
    if number == 0.0 {
        return Ok(format!("{sign}0.0"));
    }
    let shortest = format!("{:?}", number.abs());
    let (mantissa, exponent) = shortest
        .split_once('e')
        .map_or((shortest.as_str(), 0), |(m, e)| {
            (m, e.parse::<i32>().unwrap_or(0))
        });
    let mut position = mantissa.find('.').unwrap_or(mantissa.len()) as i32 + exponent;
    let mut digits = mantissa.replace('.', "");
    while digits.starts_with('0') {
        digits.remove(0);
        position -= 1;
    }
    while digits.ends_with('0') {
        digits.pop();
    }
    let exponent = position - 1;
    let body = if !(-4..16).contains(&exponent) {
        let fraction = if digits.len() > 1 {
            format!(".{}", &digits[1..])
        } else {
            String::new()
        };
        format!(
            "{}{fraction}e{}{abs:02}",
            &digits[..1],
            if exponent < 0 { "-" } else { "+" },
            abs = exponent.abs()
        )
    } else if position <= 0 {
        format!("0.{}{}", "0".repeat((-position) as usize), digits)
    } else if position as usize >= digits.len() {
        format!(
            "{}{}.0",
            digits,
            "0".repeat(position as usize - digits.len())
        )
    } else {
        format!(
            "{}.{}",
            &digits[..position as usize],
            &digits[position as usize..]
        )
    };
    Ok(format!("{sign}{body}"))
}
