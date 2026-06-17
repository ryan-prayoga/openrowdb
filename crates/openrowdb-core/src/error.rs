use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum CoreError {
    #[error("invalid address: {0}")]
    InvalidAddress(String),

    #[error("connection failed: {0}")]
    ConnectionFailed(String),

    #[error("query failed: {0}")]
    QueryFailed(String),
}