//
//  ReportIssueSheet.swift
//  Curious Places
//

import SwiftUI

/// "Report an Issue" for a place or a fact (the Expo report modal).
struct ReportIssueSheet: View {
    let source: IssueSource
    let onSubmit: (IssueType, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var issueType = IssueType.incorrectInfo
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                // At the top, so it's visible at the sheet's medium height.
                if failed {
                    Section {
                        Text("Couldn't send your report. Please try again.")
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    Picker("Issue", selection: $issueType) {
                        ForEach(IssueType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("What's wrong?").sectionTitleStyle()
                }
                .listRowBackground(Theme.surface)

                if issueType == .other {
                    Section {
                        TextField("Tell us more…", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                            .onChange(of: details) {
                                if details.count > IssueReport.maxDescriptionLength {
                                    details = String(details.prefix(IssueReport.maxDescriptionLength))
                                }
                            }
                    } footer: {
                        Text("\(IssueReport.maxDescriptionLength - details.count) characters left")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .themedList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Send", action: submit)
                            .disabled(!canSubmit)
                    }
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        switch source {
        case .place: "Report an Issue"
        case .fact: "Report a Fact"
        }
    }

    private var canSubmit: Bool {
        issueType != .other || !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        isSubmitting = true
        failed = false
        Task {
            do {
                try await onSubmit(issueType, details)
                dismiss()
            } catch {
                failed = true
            }
            isSubmitting = false
        }
    }
}
