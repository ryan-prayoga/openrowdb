/// Saved connection profile. Passwords live in the platform secret store, not here.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Connection {
    pub id: String,
    pub name: String,
    pub driver: Driver,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub database: String,
    pub ssl_mode: SslMode,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Driver {
    Postgres,
    Mysql,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SslMode {
    Disable,
    Prefer,
    Require,
}

impl Connection {
    pub fn default_port(driver: Driver) -> u16 {
        match driver {
            Driver::Postgres => 5432,
            Driver::Mysql => 3306,
        }
    }
}