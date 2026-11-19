//! Validate, compare and summarize versioned evidence receipts.

use crate::{R, read, require, source_identity::source, text};
use serde_json::{Value as V, json};
use std::path::Path;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};

pub(super) const PHASES: &[&str] = &[
    "evaluation",
    "build",
    "dry-activation",
    "activation",
    "runtime",
    "recovery",
    "vm",
];
pub(super) const SYSTEM: &[&str] = &["dry-activation", "activation", "runtime", "recovery"];

fn matches(pattern: &str, v: &V) -> bool {
    regex::Regex::new(pattern).is_ok_and(|r| v.as_str().is_some_and(|s| r.is_match(s)))
}
fn digest(v: &V) -> bool {
    matches(r"^[0-9a-f]{64}$", v)
}
pub(super) fn store(v: &V) -> bool {
    matches(
        r"^/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+_.?=-]+$",
        v,
    )
}
pub(super) fn attribute(v: &V) -> bool {
    matches(r"^[A-Za-z0-9_.-]+$", v)
}

fn valid_source(s: &V) -> R<()> {
    require(
        s.is_object()
            && matches(r"^([0-9a-f]{40}|[0-9a-f]{64})$", &s["revision"])
            && digest(&s["tree_sha256"])
            && s["dirty"].is_boolean()
            && s["lockfiles"].is_object()
            && s["submodules"].is_object(),
        "Evidence lacks complete tracked source provenance",
    )?;
    for (k, v) in s["lockfiles"].as_object().ok_or("lockfiles missing")? {
        require(!k.is_empty() && digest(v), "Invalid lockfile fingerprint")?;
    }
    for (k, v) in s["submodules"].as_object().ok_or("submodules missing")? {
        require(!k.is_empty(), "Invalid submodule name")?;
        valid_source(v)?;
    }
    Ok(())
}
fn number(v: &V, positive: bool) -> bool {
    v.as_f64()
        .is_some_and(|x| x.is_finite() && if positive { x > 0.0 } else { x >= 0.0 })
}
pub(super) fn sample(s: &V, success: bool) -> bool {
    s.is_object()
        && (s["exit_code"].is_i64() || s["exit_code"].is_u64())
        && s["timed_out"].is_boolean()
        && s["descendants_remained"].is_boolean()
        && [
            "elapsed_seconds",
            "peak_rss_kib",
            "user_seconds",
            "system_seconds",
        ]
        .iter()
        .all(|k| {
            number(
                &s[k],
                success && ["elapsed_seconds", "peak_rss_kib"].contains(k),
            )
        })
        && s["log"].as_str().is_some_and(|s| {
            !s.is_empty()
                && s != "."
                && s != ".."
                && Path::new(s).file_name().is_some_and(|n| n == s)
        })
        && (!success
            || (s["exit_code"] == 0
                && s["timed_out"] == false
                && s["descendants_remained"] == false))
}
fn valid_config(c: &V) -> bool {
    (c["status"] == "captured" && digest(&c["sha256"]))
        || (c["status"] == "unavailable" && c["reason"].as_str().is_some_and(|s| !s.is_empty()))
}
fn date(v: &V) -> R<OffsetDateTime> {
    Ok(OffsetDateTime::parse(
        v.as_str().ok_or("date missing")?,
        &Rfc3339,
    )?)
}
pub(super) fn validate_receipt(r: &V) -> R<()> {
    require(
        r["schema"].as_u64() == Some(1),
        "Evidence is missing its supported schema",
    )?;
    for k in [
        "target",
        "check",
        "system",
        "date",
        "finished",
        "phase",
        "status",
        "cache_condition",
    ] {
        require(
            r[k].as_str().is_some_and(|s| !s.is_empty()),
            "Evidence is missing required workload or date fields",
        )?;
    }
    require(
        PHASES.contains(&text(&r["phase"]))
            && ["passed", "failed", "invalid", "skipped"].contains(&text(&r["status"]))
            && ["warm", "cold", "mixed", "unspecified"].contains(&text(&r["cache_condition"])),
        "Unsupported evidence phase, status or cache condition",
    )?;
    require(
        matches(r"^[A-Za-z0-9_]+-(linux|darwin)$", &r["system"]),
        "Unsupported execution platform",
    )?;
    let start = date(&r["date"])?;
    let end = date(&r["finished"])?;
    require(
        start <= end && end <= OffsetDateTime::now_utc(),
        "Evidence dates must be ordered timezone-aware past timestamps",
    )?;
    require(
        digest(&r["command_sha256"]) && digest(&r["environment_sha256"]),
        "Evidence lacks command or environment fingerprints",
    )?;
    valid_source(&r["source"])?;
    require(
        valid_config(&r["nix_configuration"]),
        "Evidence lacks valid Nix configuration observation",
    )?;
    let count = r["expected_runs"]
        .as_u64()
        .filter(|n| *n > 0)
        .ok_or("Evidence lacks expected repetitions")?;
    let samples = r["measurements"]
        .as_array()
        .ok_or("Evidence lacks measurements")?;
    require(
        r["kind"] == if count > 1 { "benchmark" } else { "check" },
        "Evidence kind disagrees with repetitions",
    )?;
    require(
        samples.len() as u64 <= count && samples.iter().all(|s| sample(s, false)),
        "Evidence contains malformed measurements",
    )?;
    if r["status"] == "passed" {
        require(
            samples.len() as u64 == count && samples.iter().all(|s| sample(s, true)),
            "Passed evidence requires complete successful finite measurements",
        )?;
    } else {
        require(
            r["reason"].as_str().is_some_and(|s| !s.trim().is_empty()),
            "Unsuccessful evidence must explain failure or omission",
        )?;
    }
    require(
        r["status"] != "skipped" || samples.is_empty(),
        "Skipped checks cannot contain executed observations",
    )?;
    require(
        r["installable"].is_null() || attribute(&r["installable"]),
        "Invalid output attribute",
    )?;
    if r["status"] == "passed" {
        let system = SYSTEM.contains(&text(&r["phase"]));
        if system
            || (r["phase"] == "build" && r["check"] == "full-system")
            || !r["installable"].is_null()
        {
            require(
                attribute(&r["installable"]) && store(&r["system_path"]),
                "System evidence requires realized candidate output",
            )?;
        }
        if system {
            require(
                digest(&r["build_receipt_sha256"]),
                "System evidence requires matching prior build provenance",
            )?;
            require(
                r.get("active_system_before").is_some() && r.get("active_system_after").is_some(),
                "System evidence lacks active-generation observations",
            )?;
            let before = &r["active_system_before"];
            let after = &r["active_system_after"];
            require(
                [before, after].iter().all(|v| v.is_null() || store(v)),
                "Invalid active-generation output",
            )?;
            if ["runtime", "recovery"].contains(&text(&r["phase"])) {
                require(
                    *before == r["system_path"],
                    "Runtime evidence began on a different generation",
                )?;
            }
            if r["phase"] == "dry-activation" {
                require(before == after, "Dry activation changed active generation")?;
            } else {
                require(
                    *after == r["system_path"],
                    "System evidence finished on a different generation",
                )?;
            }
        }
    }
    Ok(())
}
pub(super) fn read_receipt(p: &Path) -> R<V> {
    let r = read(p)?;
    validate_receipt(&r)?;
    Ok(r)
}

fn median(v: &[f64]) -> f64 {
    let n = v.len();
    if n % 2 == 1 {
        v[n / 2]
    } else {
        (v[n / 2 - 1] + v[n / 2]) / 2.0
    }
}
pub(super) fn compare(left: &V, right: &V, budget: f64) -> R<V> {
    validate_receipt(left)?;
    validate_receipt(right)?;
    require(
        budget.is_finite() && budget >= 0.0,
        "Regression budget must be finite and nonnegative",
    )?;
    require(
        ["warm", "cold"].contains(&text(&left["cache_condition"])),
        "Comparison needs an explicit warm or cold cache condition",
    )?;
    require(
        left["nix_configuration"]["status"] == "captured"
            && right["nix_configuration"]["status"] == "captured",
        "Comparison requires captured effective Nix client configuration",
    )?;
    let fields = [
        "target",
        "check",
        "phase",
        "system",
        "cache_condition",
        "command_sha256",
        "environment_sha256",
        "nix_configuration",
    ];
    require(
        fields.iter().all(|f| left[f] == right[f]),
        "Benchmark workload, phase, platform, environment or cache conditions differ",
    )?;
    require(
        left["status"] == "passed" && right["status"] == "passed",
        "Failed or invalid trials cannot support a comparison",
    )?;
    let l = left["measurements"].as_array().ok_or("missing samples")?;
    let r = right["measurements"].as_array().ok_or("missing samples")?;
    require(
        l.len() >= 3 && r.len() >= 3,
        "A comparison needs at least three successful trials per source",
    )?;
    let mut metrics = json!({});
    let mut passed = true;
    for name in ["elapsed_seconds", "peak_rss_kib"] {
        let mut a = l
            .iter()
            .map(|s| s[name].as_f64().unwrap_or(f64::NAN))
            .collect::<Vec<_>>();
        let mut b = r
            .iter()
            .map(|s| s[name].as_f64().unwrap_or(f64::NAN))
            .collect::<Vec<_>>();
        a.sort_by(f64::total_cmp);
        b.sort_by(f64::total_cmp);
        let old = median(&a);
        let new = median(&b);
        let change = (new / old - 1.0) * 100.0;
        require(
            old > 0.0 && [old, new, change].iter().all(|x| x.is_finite()),
            "Measurement range exceeds finite comparison arithmetic",
        )?;
        let within = change <= budget;
        passed &= within;
        metrics[name] = json!({"baseline_median":old,"candidate_median":new,"baseline_range":[a[0],a[a.len()-1]],"candidate_range":[b[0],b[b.len()-1]],"change_percent":change,"within_budget":within,"ranges_overlap":a[0].max(b[0])<=a[a.len()-1].min(b[b.len()-1])});
    }
    let workload = fields
        .iter()
        .map(|f| ((*f).into(), left[f].clone()))
        .collect::<serde_json::Map<_, _>>();
    Ok(
        json!({"schema":1,"status":if passed{"passed"}else{"failed"},"baseline_source":left["source"],"baseline_date":left["date"],"candidate_date":right["date"],"workload":workload,"candidate_source":right["source"],"budget_percent":budget,"metrics":metrics}),
    )
}
pub(super) fn coverage(source_path: &Path, manifest: &V, records: &[V]) -> R<V> {
    require(
        manifest["schema"].as_u64() == Some(1),
        "Validation manifest must declare a nonempty check list",
    )?;
    let checks = manifest["checks"]
        .as_array()
        .filter(|a| !a.is_empty())
        .ok_or("Validation manifest must declare a nonempty check list")?;
    let fields = ["target", "check", "phase", "system"];
    let mut keys = std::collections::BTreeSet::new();
    let mut required = false;
    for c in checks {
        require(
            fields
                .iter()
                .all(|f| c[f].as_str().is_some_and(|s| !s.is_empty()))
                && PHASES.contains(&text(&c["phase"]))
                && matches(r"^[A-Za-z0-9_]+-(linux|darwin)$", &c["system"])
                && c.get("required").is_none_or(V::is_boolean),
            "Duplicate or invalid validation requirement",
        )?;
        require(
            keys.insert(fields.map(|f| text(&c[f]).to_owned())),
            "Duplicate validation requirement",
        )?;
        required |= c["required"] != false;
    }
    require(
        required,
        "Validation manifest must require at least one check",
    )?;
    for r in records {
        validate_receipt(r)?;
    }
    let identity = source(source_path)?;
    let mut rows = vec![];
    for c in checks {
        let mut latest: Option<&V> = None;
        for r in records {
            if r["source"] != identity || !fields.iter().all(|f| r[f] == c[f]) {
                continue;
            }
            let rank = |r: &V| {
                ["passed", "skipped", "failed", "invalid"]
                    .iter()
                    .position(|x| *x == text(&r["status"]))
                    .unwrap_or(0)
            };
            if latest.is_none_or(|l| {
                (date(&r["finished"]).ok(), rank(r)) > (date(&l["finished"]).ok(), rank(l))
            }) {
                latest = Some(r);
            }
        }
        let mut row = c.clone();
        row["status"] = latest
            .map(|r| r["status"].clone())
            .unwrap_or(json!("missing"));
        for f in ["date", "finished"] {
            row[f] = latest.map(|r| r[f].clone()).unwrap_or(V::Null);
        }
        rows.push(row);
    }
    let passed = rows
        .iter()
        .filter(|r| r["required"] != false)
        .all(|r| r["status"] == "passed");
    Ok(
        json!({"schema":1,"source":identity,"checks":rows,"status":if passed{"passed"}else{"incomplete"}}),
    )
}
