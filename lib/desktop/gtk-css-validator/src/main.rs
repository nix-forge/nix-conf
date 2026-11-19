use std::process::ExitCode;

#[cfg(target_os = "linux")]
fn main() -> ExitCode {
    use std::os::unix::ffi::OsStrExt;
    let args: Vec<_> = std::env::args_os().collect();
    if args.len() != 2 {
        eprintln!("usage: check-gtk-css FILE");
        return ExitCode::from(2);
    }
    let Ok(path) = std::ffi::CString::new(args[1].as_bytes()) else {
        return ExitCode::FAILURE;
    };
    if native::validate(&path) {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

#[cfg(not(target_os = "linux"))]
fn main() -> ExitCode {
    eprintln!("check-gtk-css is supported on Linux only");
    ExitCode::FAILURE
}

#[cfg(target_os = "linux")]
#[allow(
    unsafe_code,
    reason = "native ABI adapter with locally documented ownership and lifetimes"
)]
mod native {
    use std::ffi::{CStr, c_char, c_int, c_uint, c_ulong, c_void};

    // GLib GError (gerror.h): GQuark domain, gint code, gchar *message.
    #[repr(C)]
    struct GError {
        domain: c_uint,
        code: c_int,
        message: *mut c_char,
    }

    unsafe extern "C" {
        fn gtk_css_provider_new() -> *mut c_void;
        fn gtk_css_provider_load_from_path(provider: *mut c_void, path: *const c_char);
        fn gtk_css_parser_warning_quark() -> c_uint;
        fn g_signal_connect_data(
            instance: *mut c_void,
            signal: *const c_char,
            handler: Option<unsafe extern "C" fn()>,
            data: *mut c_void,
            destroy: Option<unsafe extern "C" fn(*mut c_void, *mut c_void)>,
            flags: c_uint,
        ) -> c_ulong;
        fn g_object_unref(object: *mut c_void);
        fn g_printerr(format: *const c_char, ...);
    }

    struct Provider(*mut c_void);
    impl Drop for Provider {
        fn drop(&mut self) {
            // SAFETY: own exactly the reference returned by gtk_css_provider_new.
            unsafe { g_object_unref(self.0) };
        }
    }

    // The context remains alive until the provider is destroyed. The callback
    // performs no Rust allocation, formatting, indexing, or unwinding.
    unsafe extern "C" fn parsing_error(
        _provider: *mut c_void,
        _section: *mut c_void,
        error: *const GError,
        data: *mut c_void,
    ) {
        // SAFETY: GTK supplies a live GError and our exclusive stack context. Warnings
        // are printed but must not make an otherwise valid stylesheet fail.
        unsafe {
            g_printerr(c"%s\n".as_ptr(), (*error).message);
            if (*error).domain != gtk_css_parser_warning_quark() {
                *data.cast::<bool>() = true;
            }
        }
    }

    pub fn validate(path: &CStr) -> bool {
        let mut failed = false;
        // SAFETY: parsing requires neither gtk_init nor a display. Provider is destroyed
        // before the stack context, including on early return.
        unsafe {
            let raw = gtk_css_provider_new();
            if raw.is_null() {
                return false;
            }
            let provider = Provider(raw);
            // GCallback is GLib's erased function pointer; parsing-error's ABI is
            // (GtkCssProvider*, GtkCssSection*, const GError*, gpointer).
            let callback = std::mem::transmute::<
                unsafe extern "C" fn(*mut c_void, *mut c_void, *const GError, *mut c_void),
                unsafe extern "C" fn(),
            >(parsing_error);
            if g_signal_connect_data(
                provider.0,
                c"parsing-error".as_ptr(),
                Some(callback),
                (&raw mut failed).cast(),
                None,
                0,
            ) == 0
            {
                return false;
            }
            gtk_css_provider_load_from_path(provider.0, path.as_ptr());
        }
        !failed
    }
}
