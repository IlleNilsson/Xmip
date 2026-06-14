use prost::Message;
use std::fs;
use std::io;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct RuntimeStore {
    root: PathBuf,
}

impl RuntimeStore {
    pub fn open(root: impl Into<PathBuf>) -> io::Result<Self> {
        let root = root.into();
        fs::create_dir_all(root.join("messages"))?;
        fs::create_dir_all(root.join("interchanges"))?;
        fs::create_dir_all(root.join("audit"))?;
        Ok(Self { root })
    }

    pub fn save_message<M: Message>(&self, message_id: &str, message: &M) -> io::Result<()> {
        let mut buffer = Vec::new();
        message
            .encode(&mut buffer)
            .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))?;
        fs::write(
            self.root.join("messages").join(format!("{}.pb", message_id)),
            buffer,
        )
    }

    pub fn save_interchange<M: Message>(&self, interchange_id: &str, value: &M) -> io::Result<()> {
        let mut buffer = Vec::new();
        value
            .encode(&mut buffer)
            .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))?;
        fs::write(
            self.root
                .join("interchanges")
                .join(format!("{}.pb", interchange_id)),
            buffer,
        )
    }

    pub fn audit(&self, event: &str) -> io::Result<()> {
        let path = self.root.join("audit").join("audit.log");
        let old = fs::read_to_string(&path).unwrap_or_default();
        fs::write(path, format!("{}{}\n", old, event))
    }
}
