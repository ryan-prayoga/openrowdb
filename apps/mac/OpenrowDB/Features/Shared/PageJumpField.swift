// PageJumpField.swift
import SwiftUI

/// A 1-based page number field that jumps on commit, clamped to [1, totalPages].
struct PageJumpField: View {
    @Binding var page: Int
    let totalPages: Int

    @State private var text: String = ""

    var body: some View {
        TextField("", text: $text)
            .frame(width: 44)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .onAppear { text = "\(page + 1)" }
            .onChange(of: page) { text = "\(page + 1)" }
            .onSubmit { commit() }
    }

    private func commit() {
        guard let value = Int(text) else {
            text = "\(page + 1)"
            return
        }
        let clamped = min(max(value, 1), totalPages)
        page = clamped - 1
        text = "\(clamped)"
    }
}
