use crate::{Result, exec, output, run};
use serde::Deserialize;

// The connection has the same two wire fields wherever a mode uses virsh.
macro_rules! virsh_policy {
    ($name:ident { $($fields:tt)* }) => {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase", deny_unknown_fields)]
        pub struct $name {
            virsh: String,
            pub libvirt_uri: String,
            $($fields)*
        }

        impl $name {
            pub fn connection(&self) -> Virsh<'_> {
                Virsh { executable: &self.virsh, uri: &self.libvirt_uri }
            }
        }
    };
}

virsh_policy! {
    SetupPolicy {
        pub guest_manifest: String,
        pub network_manifest: String,
        pub pool_definition: String,
        pub pool_name: String,
        pub pool_path: String,
        #[serde(rename = "rm", default)]
        _rm: String,
        pub xml_helper: String,
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProfileGuardPolicy {
    pub guest_manifest: String,
    pub profile_marker: String,
    pub vfio_device_manifest: String,
    pub vfio_profile: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SleepHookPolicy {
    pub guest_manifest: String,
    pub systemctl: String,
    pub systemd_escape: String,
}

virsh_policy! {
    WorkstationControlPolicy {
        pub emulate_aarch64: bool,
        pub findmnt: String,
        pub guest_manifest: String,
        pub iommu_enabled: bool,
        pub ip: String,
        pub lsattr: String,
        pub network_manifest: String,
        pub pool_name: String,
        pub pool_path: String,
        pub profile_marker: String,
        pub ps: String,
        pub qemu_aarch64: String,
        pub ss: String,
        pub storage_nocow: bool,
        pub systemctl: String,
        pub systemd_escape: String,
        pub vfio_device_manifest: String,
        pub vfio_enabled: bool,
        pub vfio_profile: String,
        pub virt_host_validate: String,
        pub xml_helper: String,
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct VmPolicy {
    pub guest_manifest: String,
    pub privileged_control: String,
    pub ssh: String,
    pub sudo: String,
    pub virt_manager: String,
}

virsh_policy! {
    WindowsReconcilePolicy {
        pub autostart: bool,
        pub disk_path: String,
        pub guest_name: String,
        pub guest_uuid: String,
        pub install_marker: String,
        pub runtime_definition: String,
        pub xml_helper: String,
    }
}

virsh_policy! {
    WindowsControlPolicy {
        pub answer_template: String,
        pub authorized_keys_file: String,
        pub autologon_archive: String,
        pub autostart: bool,
        pub baseline_test: String,
        pub bootstrap_script: String,
        pub chown: String,
        pub cp: String,
        pub disk_path: String,
        pub disk_serial: String,
        pub disk_size_gi_b: u64,
        pub download_page: String,
        pub env: String,
        pub guest_name: String,
        pub guest_uuid: String,
        pub image_name: String,
        pub install: String,
        pub install_marker: String,
        pub installer_definition: String,
        pub iso_path: String,
        pub iso_sha256: String,
        pub media_inspection_directory: String,
        pub media_inspector_group: String,
        pub media_inspector_user: String,
        pub mv: String,
        pub password_file: String,
        pub prime_disk: String,
        pub private_directory: String,
        pub qemu_group: String,
        pub qemu_img: String,
        pub qemu_user: String,
        pub recipe_fingerprint: String,
        pub release: String,
        pub rm: String,
        pub runtime_definition: String,
        pub runtime_directory: String,
        pub seed_iso: String,
        pub seed_renderer: String,
        pub setpriv: String,
        pub seven_zip: String,
        pub sha256sum: String,
        pub shutdown_guest: String,
        pub ssh_keygen: String,
        pub state_directory: String,
        pub storage_root: String,
        pub virtio_iso: String,
        pub wiminfo: String,
        pub xml_helper: String,
        pub xorriso: String,
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WindowsCliPolicy {
    pub curl: String,
    pub guest_name: String,
    #[serde(rename = "install", default)]
    _install: String,
    pub iso_language: String,
    pub iso_path: String,
    pub iso_product_id: String,
    pub iso_sha256: String,
    pub iso_sha256_path: String,
    pub msdl: String,
    #[serde(rename = "mv", default)]
    _mv: String,
    pub privileged_control: String,
    #[serde(rename = "rm", default)]
    _rm: String,
    pub setup_wizard: String,
    pub sha256sum: String,
    pub ssh_keygen: String,
    pub sudo: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WindowsWizardPolicy {
    pub guest_name: String,
    pub image_name: String,
    pub iso_file_name: String,
    pub iso_sha256: String,
    pub media_description: String,
    pub private_directory: String,
    pub privileged_control: String,
    pub sudo: String,
}

pub struct Virsh<'a> {
    executable: &'a str,
    uri: &'a str,
}

impl Virsh<'_> {
    pub fn query(&self, args: &[&str]) -> Result<String> {
        let mut command_args = vec!["--connect", self.uri];
        command_args.extend_from_slice(args);
        output(self.executable, &command_args)
    }
    pub fn run(&self, args: &[&str]) -> Result {
        let mut command_args = vec!["--connect", self.uri];
        command_args.extend_from_slice(args);
        run(self.executable, &command_args)
    }
    pub fn exec(&self, args: &[&str]) -> Result {
        let mut command_args = vec!["--connect", self.uri];
        command_args.extend_from_slice(args);
        exec(self.executable, &command_args)
    }
    pub fn active(&self, guest: &str) -> bool {
        self.query(&["domid", guest]).is_ok_and(|id| id != "-")
    }
    pub fn domain(&self, guest: &str) -> bool {
        self.query(&["dominfo", guest]).is_ok()
    }
    pub fn autostart(&self, guest: &str, enabled: bool) -> Result {
        let mut args = vec!["autostart", guest];
        if !enabled {
            args.push("--disable");
        }
        self.query(&args)?;
        Ok(())
    }
}
