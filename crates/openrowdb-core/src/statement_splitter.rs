//! Semicolon-aware statement splitter (strings, identifiers, comments).
//! Port of `apps/mac/Sources/OpenrowDBCore/SQLStatementSplitter.swift`.

/// Split a SQL script into individual statements.
pub fn split_statements(sql: &str) -> Vec<String> {
    // Stub — returns the whole script trimmed until the Swift port lands.
    let trimmed = sql.trim();
    if trimmed.is_empty() {
        Vec::new()
    } else {
        vec![trimmed.to_string()]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_input_yields_nothing() {
        assert!(split_statements("   ").is_empty());
    }

    #[test]
    fn single_statement_passthrough() {
        assert_eq!(split_statements("SELECT 1;"), vec!["SELECT 1;"]);
    }
}