//! Headless OpenrowDB core — port target for `apps/mac/Sources/OpenrowDBCore`.
//!
//! Keep this crate UI-free: no GTK, no WinUI, no AppKit.

pub mod connection;
pub mod dialect;
pub mod error;
pub mod statement_splitter;

pub use connection::Connection;
pub use dialect::SqlDialect;
pub use error::CoreError;