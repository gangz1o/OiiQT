import SwiftUI

struct SubscribeSettingsSheetView: View {
    let viewState: SubscribeFormViewState
    let onSelectOption: (String, String) -> Void
    let onUpdateText: (String, String) -> Void
    let onToggle: (String, Bool) -> Void
    let onCancel: () -> Void
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewState.mediaTitle)
                            .font(.headline.weight(.bold))
                        Text("根据 MoviePilot 当前服务器能力动态生成订阅配置。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(viewState.sections) { section in
                    Section(section.title) {
                        ForEach(section.fields) { field in
                            SubscribeFormFieldRowView(
                                field: field,
                                onSelectOption: onSelectOption,
                                onUpdateText: onUpdateText,
                                onToggle: onToggle
                            )
                        }
                    }
                }

                if let statusText = viewState.statusText, !statusText.isEmpty {
                    Section {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(viewState.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                    }
                    .disabled(viewState.isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewState.confirmButtonTitle) {
                        Task {
                            await onSubmit()
                        }
                    }
                    .disabled(viewState.isSubmitting)
                }
            }
        }
    }
}

private struct SubscribeFormFieldRowView: View {
    let field: SubscribeFormFieldViewState
    let onSelectOption: (String, String) -> Void
    let onUpdateText: (String, String) -> Void
    let onToggle: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch field.control {
            case .picker:
                pickerField
            case .text:
                textField
            case .toggle:
                toggleField
            }

            if !field.footerText.isEmpty {
                Text(field.footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var pickerField: some View {
        Picker(
            field.title,
            selection: Binding(
                get: { field.selectedOptionID ?? "" },
                set: { onSelectOption(field.id, $0) }
            )
        ) {
            Text("不限制").tag("")

            ForEach(field.options) { option in
                if option.subtitle.isEmpty {
                    Text(option.title).tag(option.id)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title)
                        Text(option.subtitle)
                    }
                    .tag(option.id)
                }
            }
        }
    }

    private var textField: some View {
        TextField(
            field.placeholder.isEmpty ? field.title : field.placeholder,
            text: Binding(
                get: { field.textValue },
                set: { onUpdateText(field.id, $0) }
            ),
            axis: .vertical
        )
        .textFieldStyle(.roundedBorder)
    }

    private var toggleField: some View {
        Toggle(
            field.title,
            isOn: Binding(
                get: { field.toggleValue },
                set: { onToggle(field.id, $0) }
            )
        )
    }
}
