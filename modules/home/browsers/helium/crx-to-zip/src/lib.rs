//! Stream a CRX2/CRX3 archive's payload without loading the archive into memory.
use std::fs::{File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom};
use std::os::unix::fs::MetadataExt;
use std::path::Path;

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

fn word(source: &mut File) -> io::Result<u32> {
    let mut bytes = [0; 4];
    source.read_exact(&mut bytes)?;
    Ok(u32::from_le_bytes(bytes))
}

pub fn convert(source: &Path, destination: &Path) -> io::Result<()> {
    let mut source = File::open(source)?;
    let mut magic = [0; 4];
    source.read_exact(&mut magic)?;
    if &magic != b"Cr24" {
        return Err(invalid("not a CRX file"));
    }
    let offset = match word(&mut source)? {
        2 => 16 + u64::from(word(&mut source)?) + u64::from(word(&mut source)?),
        3 => 12 + u64::from(word(&mut source)?),
        version => return Err(invalid(&format!("unsupported CRX version: {version}"))),
    };
    let metadata = source.metadata()?;
    if offset >= metadata.len() {
        return Err(invalid("CRX header extends beyond its payload"));
    }
    // Open without truncation, then compare open file identities. This also
    // rejects hard links and symlinks without a check/open race.
    let mut target = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .open(destination)?;
    let target_metadata = target.metadata()?;
    if metadata.dev() == target_metadata.dev() && metadata.ino() == target_metadata.ino() {
        return Err(invalid("CRX input and output must be different files"));
    }
    target.set_len(0)?;
    source.seek(SeekFrom::Start(offset))?;
    io::copy(&mut source, &mut target)?;
    Ok(())
}
