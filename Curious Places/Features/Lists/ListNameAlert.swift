//
//  ListNameAlert.swift
//  Curious Places
//

import SwiftUI

extension View {
    /// An alert with a text field for naming a new list, or renaming one.
    func listNameAlert(_ title: String, isPresented: Binding<Bool>, initialName: String = "",
                       actionTitle: String, onSave: @escaping (String) -> Void) -> some View {
        modifier(ListNameAlert(title: title, isPresented: isPresented, initialName: initialName,
                               actionTitle: actionTitle, onSave: onSave))
    }
}

private struct ListNameAlert: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let initialName: String
    let actionTitle: String
    let onSave: (String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("List name", text: $name)
                Button(actionTitle) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, trimmed != initialName { onSave(trimmed) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: isPresented) {
                if isPresented { name = initialName }
            }
    }
}
