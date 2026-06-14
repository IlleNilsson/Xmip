use prost::Message;
use rocksdb::{Options, DB};
use std::io;
use std::path::PathBuf;
use std::sync::Arc;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct RuntimeStore {
    db: Arc<DB>,
}

impl RuntimeStore {
    pub fn open(root: impl Into<PathBuf>) -> io::Result<Self> {
        let mut options = Options::default();
        options.create_if_missing(true);

        let db = DB::open(&options, root.into()).map_err(to_io_error)?;
        Ok(Self { db: Arc::new(db) })
    }

    pub fn save_message<M: Message>(&self, message_id: &str, message: &M) -> io::Result<()> {
        self.put_protobuf(&key("message", message_id), message)
    }

    pub fn save_interchange<M: Message>(&self, interchange_id: &str, value: &M) -> io::Result<()> {
        self.put_protobuf(&key("interchange", interchange_id), value)
    }

    pub fn save_state<M: Message>(&self, state_id: &str, value: &M) -> io::Result<()> {
        self.put_protobuf(&key("state", state_id), value)
    }

    pub fn save_replay_checkpoint<M: Message>(
        &self,
        checkpoint_id: &str,
        value: &M,
    ) -> io::Result<()> {
        self.put_protobuf(&key("replay", checkpoint_id), value)
    }

    pub fn audit(&self, event: &str) -> io::Result<()> {
        let audit_id = Uuid::new_v4().to_string();
        self.db
            .put(key("audit", &audit_id), event.as_bytes())
            .map_err(to_io_error)
    }

    fn put_protobuf<M: Message>(&self, key: &str, value: &M) -> io::Result<()> {
        let mut buffer = Vec::new();
        value
            .encode(&mut buffer)
            .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))?;
        self.db.put(key, buffer).map_err(to_io_error)
    }
}

fn key(prefix: &str, id: &str) -> String {
    format!("{}:{}", prefix, id)
}

fn to_io_error(error: rocksdb::Error) -> io::Error {
    io::Error::new(io::ErrorKind::Other, error)
}
