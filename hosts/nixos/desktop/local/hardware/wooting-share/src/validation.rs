//! Deliberately closed typing subset of Wootility 5.4.2's native schema 15.
//! Numeric facts were checked against the shipped key maps and conversion paths;
//! this is not a copy of the vendor implementation or a firmware compatibility claim.
use crate::Result;
use serde_json::{Value, json};
use std::collections::BTreeSet;

pub const CONTRACT: &str = "ansi80he-typing-v2";

fn require(ok: bool, path: &str, message: &str) -> Result<()> {
    if ok {
        Ok(())
    } else {
        Err(format!("{path}: {message}").into())
    }
}
fn object(value: &Value, path: &str, required: &[&str], optional: &[&str]) -> Result<()> {
    let obj = value
        .as_object()
        .ok_or_else(|| format!("{path}: expected an object"))?;
    require(
        required.iter().all(|key| obj.contains_key(*key))
            && obj
                .keys()
                .all(|key| required.contains(&key.as_str()) || optional.contains(&key.as_str())),
        path,
        "missing required or unknown fields (unsupported by the typing contract)",
    )
}
fn integer(value: &Value, path: &str, low: u64, high: u64) -> Result<()> {
    require(
        value.as_u64().is_some_and(|v| (low..=high).contains(&v)),
        path,
        &format!("expected an integer in {low}..={high}"),
    )
}
fn boolean(value: &Value, path: &str) -> Result<()> {
    require(value.is_boolean(), path, "expected a boolean")
}
fn text(value: &Value, path: &str, max: usize) -> Result<()> {
    require(
        value
            .as_str()
            .is_some_and(|s| !s.is_empty() && s.len() <= max && !s.chars().any(char::is_control)),
        path,
        &format!("expected nonempty text, at most {max} UTF-8 bytes, without controls"),
    )
}
fn empty(value: &Value, path: &str) -> Result<()> {
    require(
        value.as_array().is_some_and(Vec::is_empty),
        path,
        "this feature must be an empty array in the reviewed typing subset; configure advanced features in Wootility",
    )
}
fn color(value: &Value, path: &str) -> Result<()> {
    object(value, path, &["red", "green", "blue"], &[])?;
    for key in ["red", "green", "blue"] {
        integer(&value[key], &format!("{path}/{key}"), 0, 255)?;
    }
    Ok(())
}
fn matrix(value: &Value, path: &str) -> Result<()> {
    let rows = value
        .as_array()
        .ok_or_else(|| format!("{path}: expected a 6 by 21 RGB matrix"))?;
    require(rows.len() == 6, path, "expected six rows")?;
    for (row, values) in rows.iter().enumerate() {
        let values = values
            .as_array()
            .ok_or_else(|| format!("{path}/{row}: expected a row"))?;
        require(
            values.len() == 21,
            path,
            "each row must have 21 explicit cells",
        )?;
        for (col, cell) in values.iter().enumerate() {
            if !cell.is_null() {
                color(cell, &format!("{path}/{row}/{col}"))?;
            }
        }
    }
    Ok(())
}
// Union of the basic, extended/media and special all-lists resolved by Nn(byte).
// Gaps are meaningful: 47, 98, 211 and 255, for example, do not resolve here.
fn keycode(value: u64) -> bool {
    matches!(value, 1..=46 | 48..=97 | 99..=119 | 192..=210 | 212..=220 | 224..=247)
}
// Reviewed native remap coordinate set, not a claim about a physical switch mask.
const COLUMNS: [&[u64]; 6] = [
    &[0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16],
    &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
    &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16],
    &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14],
    &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15],
    &[0, 1, 2, 3, 4, 6, 8, 9, 10, 11, 12, 14, 15, 16],
];
fn remaps(value: &Value) -> Result<()> {
    let layers = value.as_array().ok_or("/remap: expected layers")?;
    require(
        layers.len() == 2,
        "/remap",
        "the reviewed typing contract requires main and Fn layers",
    )?;
    for (layer, entries) in layers.iter().enumerate() {
        let path = format!("/remap/{layer}");
        let entries = entries
            .as_array()
            .ok_or_else(|| format!("{path}: expected an array"))?;
        require(!entries.is_empty(), &path, "empty layers are unsupported")?;
        let mut positions = BTreeSet::new();
        for (i, entry) in entries.iter().enumerate() {
            let p = format!("{path}/{i}");
            object(entry, &p, &["index", "value"], &[])?;
            object(
                &entry["index"],
                &format!("{p}/index"),
                &["rowNr", "colNr"],
                &[],
            )?;
            integer(&entry["index"]["rowNr"], &format!("{p}/index/rowNr"), 0, 5)?;
            let row = entry["index"]["rowNr"].as_u64().ok_or("invalid row")? as usize;
            let col = entry["index"]["colNr"]
                .as_u64()
                .ok_or_else(|| format!("{p}: invalid column"))?;
            require(
                COLUMNS[row].contains(&col) && positions.insert((row, col)),
                &p,
                "unknown or duplicate reviewed remap coordinate",
            )?;
            let code = entry["value"]
                .as_u64()
                .ok_or_else(|| format!("{p}/value: expected a native Wooting keycode"))?;
            require(
                keycode(code),
                &format!("{p}/value"),
                "unknown native Wooting keycode; raw USB HID usages are not interchangeable",
            )?;
            if row == 5 && col == 12 {
                require(
                    code == 231,
                    &p,
                    "preserve the dedicated Fn key (231) on both layers",
                )?;
            }
        }
        require(
            positions.contains(&(5, 12)),
            &path,
            "explicit dedicated Fn mapping is required",
        )?;
        if layer == 0 {
            require(
                positions.len() == COLUMNS.iter().map(|v| v.len()).sum::<usize>(),
                &path,
                "main layer must cover the complete reviewed coordinate set",
            )?;
        }
    }
    Ok(())
}
fn analog(value: &Value) -> Result<()> {
    object(
        value,
        "/analog",
        &[
            "actPoint",
            "enableDigital",
            "rapidTrigger",
            "rapidTriggerSensitivity",
            "rapidTriggerStrictActuationRange",
            "tachyonMode",
            "tachyonModeFocus",
            "dksTickRate",
            "perKeyRapidTrigger",
        ],
        &["rapidTriggerSecondarySensitivity"],
    )?;
    for key in ["actPoint", "rapidTriggerSensitivity"] {
        integer(
            &value[key],
            &format!(
                "/analog/{key} (raw 14-bit units; 0..4 triggers Wootility's legacy migration)"
            ),
            5,
            16383,
        )?;
    }
    if let Some(secondary) = value.get("rapidTriggerSecondarySensitivity")
        && !secondary.is_null()
    {
        integer(
            secondary,
            "/analog/rapidTriggerSecondarySensitivity (raw units)",
            5,
            16383,
        )?;
    }
    for key in [
        "enableDigital",
        "rapidTrigger",
        "rapidTriggerStrictActuationRange",
        "tachyonMode",
    ] {
        boolean(&value[key], &format!("/analog/{key}"))?;
    }
    // This task is the digital typing profile. Per-key/global RT combinations,
    // special Tachyon modes and disabled digital input need separate app review.
    require(
        value["enableDigital"] == true
            && value["rapidTrigger"] == false
            && value["rapidTriggerStrictActuationRange"] == true
            && value["tachyonMode"] == false
            && value["tachyonModeFocus"] == 0,
        "/analog",
        "reviewed typing mode requires digital input, RT off, strict range and Tachyon off/focus 0",
    )?;
    integer(&value["dksTickRate"], "/analog/dksTickRate", 0, 2)?;
    empty(&value["perKeyRapidTrigger"], "/analog/perKeyRapidTrigger")
}
fn rgb(value: &Value) -> Result<()> {
    object(
        value,
        "/rgb",
        &[
            "brightness",
            "capsColor",
            "fnLockColor",
            "kbdArray",
            "layers",
            "effects",
        ],
        &["scrollLockColor", "numLockColor"],
    )?;
    integer(&value["brightness"], "/rgb/brightness", 0, 255)?;
    for key in [
        "capsColor",
        "fnLockColor",
        "scrollLockColor",
        "numLockColor",
    ] {
        if let Some(c) = value.get(key) {
            color(c, &format!("/rgb/{key}"))?;
        }
    }
    matrix(&value["kbdArray"], "/rgb/kbdArray")?;
    let layers = value["layers"]
        .as_array()
        .ok_or("/rgb/layers: expected an array")?;
    require(
        layers.len() == 1,
        "/rgb/layers",
        "expected the reviewed Fn RGB layer",
    )?;
    matrix(&layers[0], "/rgb/layers/0")?;
    object(&value["effects"], "/rgb/effects", &["layers"], &[])?;
    empty(&value["effects"]["layers"], "/rgb/effects/layers")
}
fn gamepad(value: &Value) -> Result<()> {
    object(value, "/gamepad", &["mapping", "profile"], &[])?;
    let m = &value["mapping"];
    object(
        m,
        "/gamepad/mapping",
        &["mappingType", "gamepadMappingOverride", "mappings"],
        &[],
    )?;
    require(
        m["mappingType"] == 0 && m["gamepadMappingOverride"] == false,
        "/gamepad/mapping",
        "reviewed typing mode requires mappingType 0 and no gamepad override",
    )?;
    empty(&m["mappings"], "/gamepad/mapping/mappings")?;
    let p = &value["profile"];
    object(p, "/gamepad/profile", &["angles", "mainCurve"], &[])?;
    let a = &p["angles"];
    object(
        a,
        "/gamepad/profile/angles",
        &[
            "fortniteStrafeAngle",
            "joystickAngleAdjustment",
            "joystickShape",
            "snappyJoystick",
        ],
        &[],
    )?;
    boolean(
        &a["fortniteStrafeAngle"],
        "/gamepad/profile/angles/fortniteStrafeAngle",
    )?;
    boolean(
        &a["snappyJoystick"],
        "/gamepad/profile/angles/snappyJoystick",
    )?;
    integer(
        &a["joystickAngleAdjustment"],
        "/gamepad/profile/angles/joystickAngleAdjustment",
        0,
        90,
    )?;
    require(
        a["joystickShape"] == 0,
        "/gamepad/profile/angles/joystickShape",
        "only reviewed shape 0 is supported",
    )?;
    object(
        &p["mainCurve"],
        "/gamepad/profile/mainCurve",
        &["point1", "point2", "point3", "point4"],
        &[],
    )?;
    let mut previous = None;
    for key in ["point1", "point2", "point3", "point4"] {
        let point = &p["mainCurve"][key];
        let path = format!("/gamepad/profile/mainCurve/{key}");
        object(point, &path, &["x", "y"], &[])?;
        for axis in ["x", "y"] {
            integer(&point[axis], &format!("{path}/{axis}"), 0, 255)?;
        }
        let x = point["x"].as_u64().ok_or("invalid curve x")?;
        require(
            previous.is_none_or(|last| last < x),
            &path,
            "curve x coordinates must increase",
        )?;
        previous = Some(x);
    }
    Ok(())
}
fn lightbar(value: &Value) -> Result<()> {
    object(
        value,
        "/lightbar",
        &["inheritGlobal", "isEnabled", "layers"],
        &[],
    )?;
    boolean(&value["inheritGlobal"], "/lightbar/inheritGlobal")?;
    boolean(&value["isEnabled"], "/lightbar/isEnabled")?;
    let layers = value["layers"]
        .as_array()
        .ok_or("/lightbar/layers: expected an array")?;
    require(
        layers.len() <= 1,
        "/lightbar/layers",
        "only the reviewed optional solid Caps Lock indicator is supported",
    )?;
    for layer in layers {
        let path = "/lightbar/layers/0";
        object(layer, path, &["condition", "effect", "title", "uid"], &[])?;
        text(&layer["title"], "/lightbar/layers/0/title", 128)?;
        require(
            layer["uid"].as_str().is_some_and(|s| {
                !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit()) && s.parse::<u64>().is_ok()
            }),
            path,
            "uid must be a decimal unsigned 64-bit string",
        )?;
        let condition = json!({"groups":[{"conditions":[{"condition":{"onMatch":{"comparisonValue":{"value":{"constant":1,"oneofKind":"constant"}},"datapoint":{"id":3,"isInternal":true},"operator":0},"oneofKind":"onMatch"}}],"type":0}],"type":0});
        require(
            layer["condition"] == condition,
            path,
            "only the reviewed Caps Lock condition is supported",
        )?;
        let e = &layer["effect"];
        object(e, "/lightbar/layers/0/effect", &["oneofKind", "solid"], &[])?;
        require(
            e["oneofKind"] == "solid",
            path,
            "only a solid lightbar effect is supported",
        )?;
        object(&e["solid"], path, &["canvas", "colour"], &[])?;
        color(
            &e["solid"]["colour"],
            "/lightbar/layers/0/effect/solid/colour",
        )?;
        let canvas = &e["solid"]["canvas"];
        object(canvas, path, &["oneofKind", "lightbar"], &[])?;
        require(
            canvas["oneofKind"] == "lightbar",
            path,
            "expected lightbar canvas",
        )?;
        object(&canvas["lightbar"], path, &["start", "end"], &[])?;
        for key in ["start", "end"] {
            integer(&canvas["lightbar"][key], path, 0, 9)?;
        }
        require(
            canvas["lightbar"]["start"].as_u64() <= canvas["lightbar"]["end"].as_u64(),
            path,
            "lightbar start must not exceed end",
        )?;
    }
    Ok(())
}

pub fn validate(profile: &Value) -> Result<()> {
    object(
        profile,
        "/",
        &[
            "version",
            "name",
            "metadata",
            "desc",
            "target",
            "rgb",
            "analog",
            "dks",
            "gamepad",
            "customActuations",
            "akc",
            "remap",
            "lightbar",
        ],
        &[],
    )?;
    require(
        profile["version"] == 15 && profile["target"] == json!({"device":10,"layout":0}),
        "/target",
        "requires schema 15, device 10 (80HE), layout 0 (ANSI)",
    )?;
    text(&profile["name"], "/name", 30)?;
    require(profile["desc"].is_string(), "/desc", "expected a string")?;
    object(&profile["metadata"], "/metadata", &["icon", "color"], &[])?;
    if !profile["metadata"]["icon"].is_null() {
        text(&profile["metadata"]["icon"], "/metadata/icon", 128)?;
    }
    if !profile["metadata"]["color"].is_null() {
        color(&profile["metadata"]["color"], "/metadata/color")?;
    }
    for key in ["dks", "akc", "customActuations"] {
        empty(&profile[key], &format!("/{key}"))?;
    }
    remaps(&profile["remap"])?;
    analog(&profile["analog"])?;
    rgb(&profile["rgb"])?;
    gamepad(&profile["gamepad"])?;
    lightbar(&profile["lightbar"])
}

/// Separate application-content comparison. Never used to relax cloud equality.
pub fn compare_import(desired: &Value, imported: &Value) -> Result<()> {
    let mut imported = imported.clone();
    if let Some(guid) = imported.as_object_mut().and_then(|obj| obj.remove("guid")) {
        require(guid.is_string(), "/guid", "unexpected server identity type")?;
    }
    validate(desired)?;
    validate(&imported)?;
    require(
        imported["desc"] == desired["desc"] || imported["desc"] == "~",
        "/desc",
        "unexpected description change",
    )?;
    let normalize = |mut p: Value| -> Result<Value> {
        p["desc"] = json!("~");
        for key in ["scrollLockColor", "numLockColor"] {
            if p["rgb"].get(key).is_none() {
                p["rgb"][key] = json!({"red":255,"green":255,"blue":255});
            }
        }
        if p["analog"]["rapidTriggerSecondarySensitivity"].is_null() {
            p["analog"]
                .as_object_mut()
                .ok_or("invalid analog")?
                .remove("rapidTriggerSecondarySensitivity");
        }
        for layer in p["remap"].as_array_mut().ok_or("invalid remap")? {
            layer
                .as_array_mut()
                .ok_or("invalid layer")?
                .sort_by_key(|entry| {
                    (
                        entry["index"]["rowNr"].as_u64(),
                        entry["index"]["colNr"].as_u64(),
                    )
                });
        }
        Ok(p)
    };
    let expected = normalize(desired.clone())?;
    let actual = normalize(imported)?;
    fn difference(expected: &Value, actual: &Value, path: &str) -> Option<String> {
        if expected == actual {
            return None;
        }
        if let (Some(a), Some(b)) = (expected.as_object(), actual.as_object()) {
            let keys: BTreeSet<_> = a.keys().chain(b.keys()).collect();
            for key in keys {
                let p = format!("{path}/{}", key.replace('~', "~0").replace('/', "~1"));
                if let Some(d) = difference(&expected[key], &actual[key], &p) {
                    return Some(d);
                }
            }
        } else if let (Some(a), Some(b)) = (expected.as_array(), actual.as_array())
            && a.len() == b.len()
        {
            for (i, (a, b)) in a.iter().zip(b).enumerate() {
                if let Some(d) = difference(a, b, &format!("{path}/{i}")) {
                    return Some(d);
                }
            }
        }
        Some(if path.is_empty() {
            "/".to_owned()
        } else {
            path.to_owned()
        })
    }
    if let Some(path) = difference(&expected, &actual, "") {
        return Err(format!("imported content differs at {path}; no import match claimed").into());
    }
    Ok(())
}
