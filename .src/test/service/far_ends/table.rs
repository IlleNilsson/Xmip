//! A database file a sqlite Send Location inserts its rows in: its far end
//! is the file, which this test reads as a sqlite Receive Location would,
//! once a row is there. The crate's own loopback names its file per thread
//! and its row by a round, which a node's Send Location knows nothing of.

use std::path::Path;

use xmip_transport::FarEnd;

use super::BOUND;

/// The file a sqlite Send Location inserts in, and its name as an address
/// writes it.
pub(super) struct Table {
    path: std::path::PathBuf,
    named: String,
}

impl Table {
    /// The file `sqlite/inbox.sqlite` under `directory`.
    pub(super) fn under(directory: &Path) -> Box<dyn FarEnd> {
        let path = directory.join("sqlite").join("inbox.sqlite");
        let named = path.display().to_string().replace('\\', "/");
        Box::new(Self { path, named })
    }
}

impl FarEnd for Table {
    fn address(&self) -> &str {
        &self.named
    }

    /// The first row, as soon as the file holds one, taken as a Receive
    /// Location takes it; told by the file's folder changing, never by a
    /// poll.
    fn take_one(self: Box<Self>) -> xmip_transport::Result<xmip_transport::Taken> {
        let folder = self.path.parent().expect("the file's folder").to_path_buf();
        std::fs::create_dir_all(&folder).expect("the file's folder");
        let (changed, _watch) = crate::watched(&folder);
        let queue = xmip_transport_sqlite::SqliteTransport::new(&self.path);
        let found = std::cell::RefCell::new(None);
        let deadline = std::time::Instant::now() + BOUND;
        crate::told(&changed, deadline, || {
            if found.borrow().is_none() {
                let row = queue.take(1).ok().and_then(|rows| rows.into_iter().next());
                *found.borrow_mut() = row;
            }
            found.borrow().is_some()
        });
        found.into_inner().map_or_else(
            || Err(xmip_transport::TransportError::permanent("no row arrived")),
            xmip_transport::Arrived::taken,
        )
    }
}
