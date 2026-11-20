use std::process::ExitCode;

#[cfg(target_os = "linux")]
fn main() -> ExitCode {
    use std::io::Read;
    let mut data = Vec::new();
    if std::io::stdin().lock().read_to_end(&mut data).is_err()
        || data.is_empty()
        || data.contains(&0)
    {
        return ExitCode::FAILURE;
    }
    if native::validate(&data) {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

#[cfg(not(target_os = "linux"))]
fn main() -> ExitCode {
    eprintln!("validate-iwd-profile is supported on Linux only");
    ExitCode::FAILURE
}

#[cfg(target_os = "linux")]
#[allow(
    unsafe_code,
    reason = "native ABI adapter with locally documented ownership and lifetimes"
)]
mod native {
    use std::ffi::{c_char, c_void};

    // ELL settings.h uses an opaque l_settings, C bool and size_t. C bool
    // corresponds to Rust bool; size_t corresponds to usize on these targets.
    unsafe extern "C" {
        fn l_settings_new() -> *mut c_void;
        fn l_settings_load_from_data(
            settings: *mut c_void,
            data: *const c_char,
            len: usize,
        ) -> bool;
        fn l_settings_get_groups(settings: *const c_void) -> *mut *mut c_char;
        fn l_settings_free(settings: *mut c_void);
        fn l_strfreev(strings: *mut *mut c_char);
    }

    struct Settings(*mut c_void);
    impl Drop for Settings {
        fn drop(&mut self) {
            // SAFETY: Settings owns the non-null pointer returned by l_settings_new.
            unsafe { l_settings_free(self.0) };
        }
    }

    struct Groups(*mut *mut c_char);
    impl Drop for Groups {
        fn drop(&mut self) {
            // SAFETY: ELL returns an owned string vector; l_strfreev also accepts NULL.
            unsafe { l_strfreev(self.0) };
        }
    }

    pub fn validate(data: &[u8]) -> bool {
        // SAFETY: ELL borrows data only during load and copies parsed settings. It
        // returns an owned NULL-terminated vector; free it before settings.
        unsafe {
            let raw = l_settings_new();
            if raw.is_null() {
                return false;
            }
            let settings = Settings(raw);
            if !l_settings_load_from_data(settings.0, data.as_ptr().cast(), data.len()) {
                return false;
            }
            let groups = Groups(l_settings_get_groups(settings.0));
            !groups.0.is_null() && !(*groups.0).is_null()
        }
    }
}
