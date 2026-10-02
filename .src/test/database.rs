//! The scripts IT operators run for Xmip Storage on a database server
//! (`deploy/database/<server>/`), held to the one schema definition the
//! backend reads and writes by (`xmip-core-persist`, `storage::schema`): a
//! script that differs from what the definition writes fails here, so the
//! two cannot drift (the owner, 2026-10-01: *We have to give PostgreSQL and
//! MSSQL IT-operators help in regards to settings and database schemas*).
//!
//! After a change to the definition, `XMIP_DATABASE_SCRIPTS=write cargo test
//! --test database --features persist` writes the scripts again; the diff
//! is then read and landed with the change.
//!
//! And Xmip Storage against a real server, where a test is given one: the
//! server named by `XMIP_TEST_POSTGRESQL` or `XMIP_TEST_SQLSERVER`, each as
//! its operators' guide says. Where neither is set the test says it was
//! skipped, and why, and passes on nothing.

use std::path::{Path, PathBuf};

use xmip_persist::storage::database::Server;
use xmip_persist::storage::schema;

/// Where a server's guide and scripts are.
fn folder(server: Server) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("deploy")
        .join("database")
        .join(server.word())
}

#[test]
fn the_scripts_are_what_the_schema_writes() {
    let writing = std::env::var("XMIP_DATABASE_SCRIPTS").is_ok_and(|asked| asked == "write");
    let mut differing = Vec::new();
    for server in Server::ALL {
        let folder = folder(server);
        for (name, text) in schema::scripts(server) {
            let path = folder.join(&name);
            if writing {
                std::fs::create_dir_all(&folder).expect("the folder");
                std::fs::write(&path, &text).expect("written");
            }
            let kept = std::fs::read_to_string(&path).unwrap_or_default();
            if kept.replace("\r\n", "\n") != text {
                differing.push(path.display().to_string());
            }
        }
        let written: Vec<String> = std::fs::read_dir(&folder)
            .expect("the folder")
            .filter_map(Result::ok)
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .filter(|name| Path::new(name).extension().is_some_and(|sql| sql == "sql"))
            .collect();
        let made: Vec<String> = schema::scripts(server)
            .into_iter()
            .map(|(n, _)| n)
            .collect();
        for stray in written.iter().filter(|name| !made.contains(name)) {
            differing.push(format!(
                "{} (no longer written)",
                folder.join(stray).display()
            ));
        }
        assert!(
            folder.join("README.md").is_file(),
            "{}: its guide",
            server.word()
        );
    }
    assert!(
        differing.is_empty(),
        "FAILED: these differ from what storage::schema writes; run \
         XMIP_DATABASE_SCRIPTS=write cargo test --test database --features persist: {differing:?}"
    );
}

/// Xmip Storage against the server `variable` names, or a skip said aloud.
fn against(server: Server, variable: &str) {
    let guide = format!("deploy/database/{}/README.md", server.word());
    let Ok(connection) = std::env::var(variable) else {
        eprintln!(
            "skipped: no {} server configured ({variable}) — see {guide}",
            server.word()
        );
        return;
    };
    panic!(
        "FAILED: {variable} names {connection}, and Xmip Storage has no {} backend built yet \
         to run against it; it follows as its own technology of xmip-core-persist ({guide})",
        server.word()
    );
}

#[test]
fn xmip_storage_keeps_its_records_on_a_postgresql_server_where_one_is_given() {
    against(Server::PostgreSql, "XMIP_TEST_POSTGRESQL");
}

#[test]
fn xmip_storage_keeps_its_records_on_a_sql_server_where_one_is_given() {
    against(Server::SqlServer, "XMIP_TEST_SQLSERVER");
}
