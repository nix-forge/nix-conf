use crate::Result;
use std::fs;

pub fn rows(contents: &str) -> impl Iterator<Item = &str> {
    contents.lines().filter(|line| !line.is_empty())
}

fn columns<'a, const N: usize>(line: &'a str, error: &str) -> Result<[&'a str; N]> {
    line.split('\t')
        .collect::<Vec<_>>()
        .try_into()
        .map_err(|_| error.into())
}

fn optional(value: &str) -> Option<String> {
    (value != "-").then(|| value.to_owned())
}

pub struct Guest {
    pub name: String,
    pub ssh_host: Option<String>,
    pub exclusive_group: Option<String>,
    pub required_profile: Option<String>,
    pub autostart: bool,
    pub inhibit_sleep: bool,
}

pub fn guests(path: &str) -> Result<Vec<Guest>> {
    let contents = fs::read_to_string(path)?;
    rows(&contents)
        .map(|line| {
            let [
                name,
                ssh_host,
                exclusive_group,
                required_profile,
                autostart,
                inhibit_sleep,
            ] = columns(line, "invalid guest manifest")?;
            Ok(Guest {
                name: name.into(),
                ssh_host: optional(ssh_host),
                exclusive_group: optional(exclusive_group),
                required_profile: optional(required_profile),
                autostart: autostart == "1",
                inhibit_sleep: inhibit_sleep == "1",
            })
        })
        .collect()
}

pub struct Network<'a> {
    pub name: &'a str,
    pub bridge: &'a str,
    pub subnet: &'a str,
    pub definition: &'a str,
}

impl<'a> Network<'a> {
    pub fn parse(line: &'a str) -> Result<Self> {
        let [name, bridge, subnet, definition] = columns(line, "invalid network manifest")?;
        Ok(Self {
            name,
            bridge,
            subnet,
            definition,
        })
    }
}

pub struct VfioDevice {
    pub name: String,
    pub pci_address: String,
    pub vendor_device_id: String,
    pub iommu_group: String,
}

pub fn vfio_devices(path: &str) -> Result<Vec<VfioDevice>> {
    let contents = fs::read_to_string(path)?;
    rows(&contents)
        .map(|line| {
            let [name, pci_address, vendor_device_id, iommu_group] =
                columns(line, "invalid VFIO device manifest")?;
            Ok(VfioDevice {
                name: name.into(),
                pci_address: pci_address.into(),
                vendor_device_id: vendor_device_id.into(),
                iommu_group: iommu_group.into(),
            })
        })
        .collect()
}
