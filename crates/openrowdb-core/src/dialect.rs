/// SQL dialect — Postgres vs MySQL introspection and quoting rules.
/// Port of `apps/mac/Sources/OpenrowDBCore/SQLDialect.swift`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SqlDialect {
    Postgres,
    Mysql,
}

impl SqlDialect {
    pub fn quote_identifier(&self, name: &str) -> String {
        match self {
            SqlDialect::Postgres => format!("\"{}\"", name.replace('"', "\"\"")),
            SqlDialect::Mysql => format!("`{}`", name.replace('`', "``")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn postgres_quotes_identifiers() {
        let d = SqlDialect::Postgres;
        assert_eq!(d.quote_identifier("users"), "\"users\"");
        assert_eq!(d.quote_identifier("weird\"name"), "\"weird\"\"name\"");
    }

    #[test]
    fn mysql_quotes_identifiers() {
        let d = SqlDialect::Mysql;
        assert_eq!(d.quote_identifier("users"), "`users`");
        assert_eq!(d.quote_identifier("weird`name"), "`weird``name`");
    }
}