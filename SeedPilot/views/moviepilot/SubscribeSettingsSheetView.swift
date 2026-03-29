import SwiftUI
import UIKit

struct SubscribeSettingsSheetView: View {
    let viewState: SubscribeFormViewState
    let onSelectOption: (String, String) -> Void
    let onToggleMultiOption: (String, String, Bool) -> Void
    let onUpdateText: (String, String) -> Void
    let onToggle: (String, Bool) -> Void
    let onCancel: () -> Void
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewState.mediaTitle)
                            .font(.headline.weight(.semibold))

                        Text(moviePilotLocalized("字段已按 MoviePilot 订阅接口重建，保存时会提交完整订阅 payload。"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    if !viewState.metadataRows.isEmpty {
                        ForEach(viewState.metadataRows) { row in
                            LabeledContent(moviePilotLocalized(row.title), value: row.value)
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text(moviePilotLocalized("订阅概览"))
                }

                ForEach(viewState.sections) { section in
                    Section(moviePilotLocalized(section.title)) {
                        ForEach(section.fields) { field in
                            SubscribeFormFieldRowView(
                                field: field,
                                onSelectOption: onSelectOption,
                                onToggleMultiOption: onToggleMultiOption,
                                onUpdateText: onUpdateText,
                                onToggle: onToggle
                            )
                        }
                    }
                }

                if let statusText = viewState.statusText, !statusText.isEmpty {
                    Section {
                        Text(moviePilotLocalized(statusText))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(moviePilotLocalized(viewState.sheetTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(moviePilotLocalized("取消"), action: onCancel)
                        .disabled(viewState.isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await onSubmit()
                        }
                    } label: {
                        if viewState.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(moviePilotLocalized(viewState.confirmButtonTitle))
                                .fontWeight(.semibold)
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
    let onToggleMultiOption: (String, String, Bool) -> Void
    let onUpdateText: (String, String) -> Void
    let onToggle: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch field.control {
            case .picker:
                pickerField
            case .multiPicker:
                multiPickerField
            case .toggle:
                toggleField
            case .text:
                singleLineTextField(keyboardType: .default)
            case .multilineText:
                multilineTextField
            case .integer:
                singleLineTextField(keyboardType: .numberPad)
            case .decimal:
                singleLineTextField(keyboardType: .decimalPad)
            case .stringList:
                stringListField
            }

            if !field.footerText.isEmpty {
                Text(moviePilotLocalized(field.footerText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var pickerField: some View {
        Menu {
            if field.allowsEmptySelection {
                Button(moviePilotLocalized("不设置")) {
                    onSelectOption(field.id, "")
                }

                if !field.options.isEmpty {
                    Divider()
                }
            }

            ForEach(field.options) { option in
                Button {
                    onSelectOption(field.id, option.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(moviePilotLocalized(option.title))
                        if !option.subtitle.isEmpty {
                            Text(moviePilotLocalized(option.subtitle))
                                .font(.caption)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldTitle
                    Text(selectedSingleOptionTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var multiPickerField: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldTitle

            Text(selectedMultiOptionTitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if field.options.isEmpty {
                Text(moviePilotLocalized("当前没有可选项"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(field.options) { option in
                    let isSelected = field.selectedOptionIDs.contains(option.id)

                    Button {
                        onToggleMultiOption(field.id, option.id, !isSelected)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(moviePilotLocalized(option.title))
                                    .foregroundStyle(.primary)

                                if !option.subtitle.isEmpty {
                                    Text(moviePilotLocalized(option.subtitle))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 8)

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? .blue : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func singleLineTextField(keyboardType: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldTitle

            TextField(
                moviePilotLocalized(field.placeholder.isEmpty ? field.title : field.placeholder),
                text: Binding(
                    get: { field.textValue },
                    set: { onUpdateText(field.id, $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
        }
    }

    private var multilineTextField: some View {
        editorField(minHeight: 120)
    }

    private var stringListField: some View {
        editorField(minHeight: 100)
    }

    private func editorField(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldTitle

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))

                if field.textValue.isEmpty {
                    Text(moviePilotLocalized(field.placeholder))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                }

                TextEditor(
                    text: Binding(
                        get: { field.textValue },
                        set: { onUpdateText(field.id, $0) }
                    )
                )
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .frame(minHeight: minHeight)
        }
    }

    private var toggleField: some View {
        Toggle(isOn: Binding(
            get: { field.toggleValue },
            set: { onToggle(field.id, $0) }
        )) {
            fieldTitle
        }
        .toggleStyle(.switch)
    }

    private var fieldTitle: some View {
        HStack(spacing: 4) {
            Text(moviePilotLocalized(field.title))
                .font(.subheadline.weight(.medium))

            if field.isRequired {
                Text("*")
                    .foregroundStyle(.red)
            }
        }
    }

    private var selectedSingleOptionTitle: String {
        guard let selectedOptionID = field.selectedOptionIDs.first,
              let selectedOption = field.options.first(where: { $0.id == selectedOptionID }) else {
            return moviePilotLocalized(field.allowsEmptySelection ? "不设置" : "请选择")
        }

        return moviePilotLocalized(selectedOption.title)
    }

    private var selectedMultiOptionTitle: String {
        let titles = field.selectedOptionIDs.compactMap { selectedID in
            field.options.first(where: { $0.id == selectedID })?.title
        }

        guard !titles.isEmpty else {
            return moviePilotLocalized("未选择站点")
        }

        if titles.count <= 3 {
            return titles.map(moviePilotLocalized).joined(separator: "、")
        }

        let visible = titles.prefix(2).map(moviePilotLocalized).joined(separator: "、")
        return "\(visible) 等 \(titles.count) 项"
    }
}
