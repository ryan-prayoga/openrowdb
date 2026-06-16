// SQLMutationsTests.swift
import XCTest
@testable import OpenrowDBCore

final class SQLMutationsTests: XCTestCase {
    private let t = TableRef(schema: "public", name: "Movie")
    private let mt = TableRef(schema: "shop", name: "orders")

    // MARK: - Literals

    func testRenderNull() {
        XCTAssertEqual(SQLDialect.postgres.render(.null), "NULL")
    }

    func testRenderTextEscapesQuotes() {
        XCTAssertEqual(SQLDialect.postgres.render(.text("O'Brien")), "'O''Brien'")
    }

    // MARK: - Insert

    func testInsertRowPostgres() {
        let sql = SQLDialect.postgres.insertRowSQL(t, columns: ["title", "year"], values: [.text("Up"), .text("2009")])
        XCTAssertEqual(sql, "INSERT INTO \"public\".\"Movie\" (\"title\", \"year\") VALUES ('Up', '2009')")
    }

    func testInsertRowWithNull() {
        let sql = SQLDialect.mysql.insertRowSQL(mt, columns: ["note"], values: [.null])
        XCTAssertEqual(sql, "INSERT INTO `shop`.`orders` (`note`) VALUES (NULL)")
    }

    func testInsertNoColumnsPostgresDefaultValues() {
        XCTAssertEqual(SQLDialect.postgres.insertRowSQL(t, columns: [], values: []),
                       "INSERT INTO \"public\".\"Movie\" DEFAULT VALUES")
    }

    func testInsertNoColumnsMySQLEmptyValues() {
        XCTAssertEqual(SQLDialect.mysql.insertRowSQL(mt, columns: [], values: []),
                       "INSERT INTO `shop`.`orders` () VALUES ()")
    }

    // MARK: - Update

    func testUpdateRowPostgres() {
        let sql = SQLDialect.postgres.updateRowSQL(
            t,
            assignments: [("title", .text("Up")), ("note", .null)],
            predicates: [("id", .text("5"))]
        )
        XCTAssertEqual(sql, "UPDATE \"public\".\"Movie\" SET \"title\" = 'Up', \"note\" = NULL WHERE \"id\" = '5'")
    }

    func testUpdateRowCompositeKeyMySQL() {
        let sql = SQLDialect.mysql.updateRowSQL(
            mt,
            assignments: [("qty", .text("3"))],
            predicates: [("order_id", .text("1")), ("line", .text("2"))]
        )
        XCTAssertEqual(sql, "UPDATE `shop`.`orders` SET `qty` = '3' WHERE `order_id` = '1' AND `line` = '2'")
    }

    // MARK: - Delete

    func testDeleteRowPostgres() {
        let sql = SQLDialect.postgres.deleteRowSQL(t, predicates: [("id", .text("9"))])
        XCTAssertEqual(sql, "DELETE FROM \"public\".\"Movie\" WHERE \"id\" = '9'")
    }

    func testDeleteRowNullPredicateUsesIsNull() {
        let sql = SQLDialect.postgres.deleteRowSQL(t, predicates: [("slug", .null)])
        XCTAssertEqual(sql, "DELETE FROM \"public\".\"Movie\" WHERE \"slug\" IS NULL")
    }

    // MARK: - Search

    func testSearchPredicatePostgres() {
        let pred = SQLDialect.postgres.searchPredicate(columns: ["title", "note"], term: "war")
        XCTAssertEqual(
            pred,
            "(POSITION(LOWER('war') IN LOWER(CAST(\"title\" AS TEXT))) > 0 OR POSITION(LOWER('war') IN LOWER(CAST(\"note\" AS TEXT))) > 0)"
        )
    }

    func testSearchPredicateMySQLUsesLocateAndChar() {
        let pred = SQLDialect.mysql.searchPredicate(columns: ["note"], term: "x")
        XCTAssertEqual(pred, "(LOCATE(LOWER('x'), LOWER(CAST(`note` AS CHAR))) > 0)")
    }

    func testSearchTermSingleQuoteEscaped() {
        let pred = SQLDialect.postgres.searchPredicate(columns: ["a"], term: "O'Brien")
        XCTAssertTrue(pred.contains("LOWER('O''Brien')"))
    }

    func testSearchRowsSQLWithSort() {
        let sql = SQLDialect.postgres.searchRowsSQL(t, columns: ["title"], term: "a", limit: 50, offset: 100,
                                                    sort: SortSpec(column: "year", ascending: false))
        XCTAssertEqual(
            sql,
            "SELECT * FROM \"public\".\"Movie\" WHERE (POSITION(LOWER('a') IN LOWER(CAST(\"title\" AS TEXT))) > 0) ORDER BY \"year\" DESC LIMIT 50 OFFSET 100"
        )
    }

    func testSearchRowsClampsNegatives() {
        let sql = SQLDialect.mysql.searchRowsSQL(mt, columns: ["note"], term: "a", limit: -1, offset: -1)
        XCTAssertTrue(sql.hasSuffix("LIMIT 0 OFFSET 0"))
    }

    func testSearchCountSQL() {
        let sql = SQLDialect.postgres.searchCountSQL(t, columns: ["title"], term: "a")
        XCTAssertEqual(
            sql,
            "SELECT COUNT(*) FROM \"public\".\"Movie\" WHERE (POSITION(LOWER('a') IN LOWER(CAST(\"title\" AS TEXT))) > 0)"
        )
    }

    // MARK: - Primary keys

    func testPrimaryKeyColumnsSQLPostgresUsesRegclass() {
        let sql = SQLDialect.postgres.primaryKeyColumnsSQL(t)
        XCTAssertTrue(sql.contains("i.indisprimary"))
        XCTAssertTrue(sql.contains("'\"public\".\"Movie\"'::regclass"))
    }

    func testPrimaryKeyColumnsSQLMySQL() {
        let sql = SQLDialect.mysql.primaryKeyColumnsSQL(mt)
        XCTAssertTrue(sql.contains("key_column_usage"))
        XCTAssertTrue(sql.contains("table_schema = 'shop'"))
        XCTAssertTrue(sql.contains("table_name = 'orders'"))
        XCTAssertTrue(sql.contains("constraint_name = 'PRIMARY'"))
    }

    // MARK: - Create table

    func testCreateTableWithPrimaryKey() {
        let columns = [
            ColumnDefinition(name: "id", type: "integer", isNullable: false, isPrimaryKey: true),
            ColumnDefinition(name: "title", type: "text", isNullable: true),
            ColumnDefinition(name: "year", type: "integer", isNullable: false, defaultValue: "0")
        ]
        let sql = SQLDialect.postgres.createTableSQL(t, columns: columns)
        XCTAssertEqual(
            sql,
            "CREATE TABLE \"public\".\"Movie\" (\"id\" integer NOT NULL, \"title\" text, \"year\" integer NOT NULL DEFAULT 0, PRIMARY KEY (\"id\"))"
        )
    }

    func testCreateTableCompositePrimaryKeyMySQL() {
        let columns = [
            ColumnDefinition(name: "a", type: "int", isNullable: false, isPrimaryKey: true),
            ColumnDefinition(name: "b", type: "int", isNullable: false, isPrimaryKey: true)
        ]
        let sql = SQLDialect.mysql.createTableSQL(mt, columns: columns)
        XCTAssertEqual(sql, "CREATE TABLE `shop`.`orders` (`a` int NOT NULL, `b` int NOT NULL, PRIMARY KEY (`a`, `b`))")
    }

    func testCreateTableNoPrimaryKeyOmitsClause() {
        let columns = [ColumnDefinition(name: "x", type: "text")]
        let sql = SQLDialect.postgres.createTableSQL(t, columns: columns)
        XCTAssertEqual(sql, "CREATE TABLE \"public\".\"Movie\" (\"x\" text)")
    }

    // MARK: - Alter / drop table

    func testDropTable() {
        XCTAssertEqual(SQLDialect.postgres.dropTableSQL(t), "DROP TABLE \"public\".\"Movie\"")
    }

    func testRenameTable() {
        XCTAssertEqual(SQLDialect.postgres.renameTableSQL(t, to: "Film"),
                       "ALTER TABLE \"public\".\"Movie\" RENAME TO \"Film\"")
    }

    func testAddColumn() {
        let col = ColumnDefinition(name: "rating", type: "numeric(3,1)", isNullable: false, defaultValue: "0")
        XCTAssertEqual(SQLDialect.postgres.addColumnSQL(t, column: col),
                       "ALTER TABLE \"public\".\"Movie\" ADD COLUMN \"rating\" numeric(3,1) NOT NULL DEFAULT 0")
    }

    func testDropColumn() {
        XCTAssertEqual(SQLDialect.mysql.dropColumnSQL(mt, column: "note"),
                       "ALTER TABLE `shop`.`orders` DROP COLUMN `note`")
    }

    func testRenameColumn() {
        XCTAssertEqual(SQLDialect.postgres.renameColumnSQL(t, column: "yr", to: "year"),
                       "ALTER TABLE \"public\".\"Movie\" RENAME COLUMN \"yr\" TO \"year\"")
    }

    func testRenameColumnMySQLUsesRenameColumn() {
        // RENAME COLUMN (not CHANGE COLUMN) so a rename can't drop NOT NULL /
        // AUTO_INCREMENT / length. Requires MySQL 8.0.1+ / MariaDB 10.5.2+.
        XCTAssertEqual(SQLDialect.mysql.renameColumnSQL(mt, column: "yr", to: "year"),
                       "ALTER TABLE `shop`.`orders` RENAME COLUMN `yr` TO `year`")
    }
}
