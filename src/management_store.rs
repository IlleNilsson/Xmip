use rusqlite::{params, Connection, Result};
use std::path::Path;

pub struct ManagementStore {
    connection: Connection,
}

impl ManagementStore {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let connection = Connection::open(path)?;
        let store = Self { connection };
        store.initialize()?;
        Ok(store)
    }

    fn initialize(&self) -> Result<()> {
        self.connection.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS nodes (
                node_name TEXT PRIMARY KEY,
                cluster_name TEXT NOT NULL,
                registered_at_utc TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS modules (
                module_name TEXT PRIMARY KEY,
                module_path TEXT NOT NULL,
                enabled INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS configuration_versions (
                configuration_name TEXT NOT NULL,
                version TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                applied_at_utc TEXT NOT NULL,
                PRIMARY KEY(configuration_name, version)
            );

            CREATE TABLE IF NOT EXISTS management_audit (
                audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_utc TEXT NOT NULL,
                event_type TEXT NOT NULL,
                event_text TEXT NOT NULL
            );
            ",
        )
    }

    pub fn register_node(
        &self,
        node_name: &str,
        cluster_name: &str,
        registered_at_utc: &str,
    ) -> Result<()> {
        self.connection.execute(
            "INSERT OR REPLACE INTO nodes(node_name, cluster_name, registered_at_utc)
             VALUES (?1, ?2, ?3)",
            params![node_name, cluster_name, registered_at_utc],
        )?;
        Ok(())
    }

    pub fn register_module(&self, module_name: &str, module_path: &str, enabled: bool) -> Result<()> {
        self.connection.execute(
            "INSERT OR REPLACE INTO modules(module_name, module_path, enabled)
             VALUES (?1, ?2, ?3)",
            params![module_name, module_path, enabled as i32],
        )?;
        Ok(())
    }

    pub fn record_configuration_version(
        &self,
        configuration_name: &str,
        version: &str,
        content_hash: &str,
        applied_at_utc: &str,
    ) -> Result<()> {
        self.connection.execute(
            "INSERT OR REPLACE INTO configuration_versions(
                configuration_name,
                version,
                content_hash,
                applied_at_utc
             ) VALUES (?1, ?2, ?3, ?4)",
            params![configuration_name, version, content_hash, applied_at_utc],
        )?;
        Ok(())
    }

    pub fn audit(&self, event_utc: &str, event_type: &str, event_text: &str) -> Result<()> {
        self.connection.execute(
            "INSERT INTO management_audit(event_utc, event_type, event_text)
             VALUES (?1, ?2, ?3)",
            params![event_utc, event_type, event_text],
        )?;
        Ok(())
    }
}
