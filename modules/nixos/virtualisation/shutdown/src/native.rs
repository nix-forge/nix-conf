//! Audited libvirt C boundary. All handles and callback context have one owner.
//! ABI declarations match libvirt-domain.h/libvirt-event.h (libvirt 12.8).
use std::{
    error::Error,
    ffi::{CStr, CString, c_char, c_int, c_uint, c_void},
    ptr,
    sync::atomic::{AtomicBool, Ordering},
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
type Handle = *mut c_void;
type Lifecycle = extern "C" fn(Handle, Handle, c_int, c_int, Handle) -> c_int;
type Timer = extern "C" fn(c_int, Handle);
type Free = Option<extern "C" fn(Handle)>;
#[link(name = "virt")]
unsafe extern "C" {
    fn virEventRegisterDefaultImpl() -> c_int;
    fn virEventRunDefaultImpl() -> c_int;
    fn virConnectOpen(uri: *const c_char) -> Handle;
    fn virConnectClose(connection: Handle) -> c_int;
    fn virDomainLookupByName(connection: Handle, name: *const c_char) -> Handle;
    fn virDomainFree(domain: Handle) -> c_int;
    fn virDomainGetUUIDString(domain: Handle, uuid: *mut c_char) -> c_int;
    fn virDomainIsActive(domain: Handle) -> c_int;
    fn virDomainShutdownFlags(domain: Handle, flags: c_uint) -> c_int;
    fn virConnectDomainEventRegister(
        connection: Handle,
        callback: Option<Lifecycle>,
        opaque: Handle,
        free: Free,
    ) -> c_int;
    fn virConnectDomainEventDeregister(connection: Handle, callback: Option<Lifecycle>) -> c_int;
    fn virEventAddTimeout(
        milliseconds: c_int,
        callback: Option<Timer>,
        opaque: Handle,
        free: Free,
    ) -> c_int;
    fn virEventRemoveTimeout(timer: c_int) -> c_int;
    fn virSetErrorFunc(opaque: Handle, callback: Option<extern "C" fn(Handle, Handle)>);
}
struct State {
    uuid: Vec<u8>,
    stopped: AtomicBool,
    expired: AtomicBool,
}
// libvirt owns the domain argument only for this callback. The opaque pointer
// borrows our heap-stable State until both registrations have been removed.
extern "C" fn lifecycle(
    _: Handle,
    domain: Handle,
    event: c_int,
    _: c_int,
    opaque: Handle,
) -> c_int {
    if event == 5 && !opaque.is_null() && !domain.is_null() {
        let mut uuid = [0 as c_char; 37];
        // SAFETY: libvirt supplies a live domain, and UUID_STRING_BUFLEN is 37.
        if unsafe { virDomainGetUUIDString(domain, uuid.as_mut_ptr()) } == 0 {
            // SAFETY: opaque is the State owned by Observer; libvirt guarantees a NUL
            // terminated UUID on success. Neither shared borrow outlives the callback.
            let (state, uuid) =
                unsafe { (&*opaque.cast::<State>(), CStr::from_ptr(uuid.as_ptr())) };
            if uuid.to_bytes() == state.uuid {
                state.stopped.store(true, Ordering::SeqCst);
            }
        }
    }
    0
}
extern "C" fn deadline(_: c_int, opaque: Handle) {
    if !opaque.is_null() {
        // SAFETY: same registered heap-stable State lifetime as lifecycle above.
        unsafe { &*opaque.cast::<State>() }
            .expired
            .store(true, Ordering::SeqCst);
    }
}
extern "C" fn silent_error(_: Handle, _: Handle) {}
struct Observer {
    connection: Handle,
    domain: Handle,
    registered: bool,
    timer: c_int,
    state: Option<Box<State>>,
}
impl Drop for Observer {
    fn drop(&mut self) {
        // SAFETY: handles were acquired from libvirt. Remove registrations while
        // State is still alive, then release domain and connection references.
        unsafe {
            let timer_failed = self.timer >= 0 && virEventRemoveTimeout(self.timer) < 0;
            let event_failed = self.registered
                && virConnectDomainEventDeregister(self.connection, Some(lifecycle)) < 0;
            if !self.domain.is_null() {
                virDomainFree(self.domain);
            }
            if !self.connection.is_null() {
                virConnectClose(self.connection);
            }
            if timer_failed || event_failed {
                // A failed deregistration cannot prove callback lifetime has ended. Leak
                // this single process-local context rather than allow a use-after-free.
                if let Some(state) = self.state.take() {
                    Box::leak(state);
                }
            }
        }
    }
}
pub(super) fn shutdown(uri: &str, name: &str, milliseconds: i32) -> Result<()> {
    let uri = CString::new(uri)?;
    let name = CString::new(name)?;
    // SAFETY: synchronous, process-local initialization before any registrations;
    // the error callback captures no borrowed state and never unwinds.
    unsafe {
        virSetErrorFunc(ptr::null_mut(), Some(silent_error));
    }
    // SAFETY: initialize the process-local event implementation before use.
    if unsafe { virEventRegisterDefaultImpl() } < 0 {
        return Err("event registration failed".into());
    }
    // SAFETY: uri is a live NUL-terminated CString; the returned handle is checked.
    let connection = unsafe { virConnectOpen(uri.as_ptr()) };
    if connection.is_null() {
        return Err("libvirt connection failed".into());
    }
    let mut observer = Observer {
        connection,
        domain: ptr::null_mut(),
        registered: false,
        timer: -1,
        state: None,
    };
    // SAFETY: connection lives in Observer and CString remains live for the call.
    observer.domain = unsafe { virDomainLookupByName(connection, name.as_ptr()) };
    if observer.domain.is_null() {
        return Err("guest lookup failed".into());
    }
    let mut uuid = [0 as c_char; 37];
    // SAFETY: Observer owns a live domain and uuid has the required 37 bytes.
    if unsafe { virDomainGetUUIDString(observer.domain, uuid.as_mut_ptr()) } < 0 {
        return Err("guest identity unavailable".into());
    }
    // SAFETY: libvirt returned a NUL-terminated UUID into the 37-byte buffer.
    observer.state = Some(Box::new(State {
        // SAFETY: the successful call above wrote a NUL-terminated UUID.
        uuid: unsafe { CStr::from_ptr(uuid.as_ptr()) }.to_bytes().to_vec(),
        stopped: AtomicBool::new(false),
        expired: AtomicBool::new(false),
    }));
    let state = observer
        .state
        .as_deref()
        .ok_or("callback context missing")?;
    let opaque = ptr::from_ref(state).cast_mut().cast::<c_void>();
    // SAFETY: State is heap-stable and Observer unregisters callbacks before
    // dropping it. The exact typed lifecycle ABI avoids function-pointer casts.
    if unsafe { virConnectDomainEventRegister(connection, Some(lifecycle), opaque, None) } < 0 {
        return Err("lifecycle subscription failed".into());
    }
    observer.registered = true;
    // SAFETY: heap-stable State survives until Observer removes this timer.
    observer.timer = unsafe { virEventAddTimeout(milliseconds, Some(deadline), opaque, None) };
    if observer.timer < 0 {
        return Err("shutdown timer failed".into());
    }
    // Subscribe before snapshot: a stop during the snapshot remains queued.
    // SAFETY: Observer retains the domain reference throughout this query.
    match unsafe { virDomainIsActive(observer.domain) } {
        0 => return Ok(()),
        1 => {}
        _ => return Err("guest state unavailable".into()),
    }
    // Guest agent first, then ACPI. A concurrently stopped guest is success.
    // SAFETY: the owned domain remains live; 2 selects the guest-agent shutdown flag.
    if unsafe { virDomainShutdownFlags(observer.domain, 2) } < 0
        // SAFETY: same live domain; 1 selects ACPI if the agent request failed.
        && unsafe { virDomainShutdownFlags(observer.domain, 1) } < 0
    {
        // SAFETY: Observer still owns the domain during this final state query.
        if unsafe { virDomainIsActive(observer.domain) } != 0 {
            return Err("graceful shutdown request failed".into());
        }
        return Ok(());
    }
    while !state.stopped.load(Ordering::SeqCst) && !state.expired.load(Ordering::SeqCst) {
        // SAFETY: the registered default event implementation blocks for native
        // descriptors/timers; it does not poll domain state or invoke Rust panics.
        if unsafe { virEventRunDefaultImpl() } < 0 {
            return Err("libvirt event loop failed".into());
        }
    }
    if !state.stopped.load(Ordering::SeqCst) {
        return Err("guest shutdown deadline exceeded".into());
    }
    Ok(())
}
