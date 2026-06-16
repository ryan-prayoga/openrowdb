// SQLFormatterTests.swift
import Foundation
import Testing
@testable import OpenrowDBCore

@Suite struct SQLFormatterTests {
    @Test func formatsSelectClauses() {
        let input = "select id,name from users where active=true order by name"
        let formatted = SQLFormatter.format(input, dialect: .postgres)
        #expect(formatted.contains("SELECT"))
        #expect(formatted.contains("\nFROM"))
        #expect(formatted.contains("\nWHERE"))
        #expect(formatted.contains("\nORDER BY"))
    }

    @Test func preservesStringLiterals() {
        let input = "SELECT 'hello, world' FROM t"
        let formatted = SQLFormatter.format(input, dialect: .postgres)
        #expect(formatted.contains("'hello, world'"))
    }

    @Test func splitsMultiStatement() {
        let input = "SELECT 1; SELECT 2"
        let formatted = SQLFormatter.format(input, dialect: .postgres)
        #expect(formatted.contains("SELECT 1"))
        #expect(formatted.contains("SELECT 2"))
        #expect(formatted.contains("\n\n"))
    }
}