import SwiftUI

struct DownloadConfigurationSheetView: View {
    let viewState: DownloadFormViewState
    let onSelectDownloader: (String) -> Void
    let onUpdateSavePath: (String) -> Void
    let onCancel: () -> Void
    let onConfirm: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(viewState.resourceTitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                } header: {
                    Text("资源")
                }

                Section {
                    if viewState.downloaders.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在加载下载器…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("下载器", selection: downloaderBinding) {
                            ForEach(viewState.downloaders) { downloader in
                                Text(downloader.name).tag(downloader.id)
                            }
                        }
                    }
                } header: {
                    Text("下载器")
                }

                Section {
                    HStack(spacing: 8) {
                        TextField("留空使用默认路径", text: savePathBinding)
                            .font(.subheadline)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        if !viewState.presetSavePaths.isEmpty {
                            Menu {
                                Button("使用默认路径") {
                                    onUpdateSavePath("")
                                }

                                Divider()

                                ForEach(viewState.presetSavePaths, id: \.self) { path in
                                    Button(path) {
                                        onUpdateSavePath(path)
                                    }
                                }
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundStyle(.blue)
                            }
                            .accessibilityLabel("选择预置目录")
                        }
                    }
                } header: {
                    Text("保存路径")
                } footer: {
                    Text(
                        viewState.presetSavePaths.isEmpty
                            ? "可选。留空将使用 MoviePilot 默认配置的保存路径。"
                            : "可选。可直接选择预置目录，或留空使用 MoviePilot 默认配置的保存路径。"
                    )
                }

                if let errorMessage = viewState.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("下载配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                        .disabled(viewState.isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await onConfirm()
                        }
                    } label: {
                        if viewState.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("下载")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(viewState.downloaders.isEmpty || viewState.isSubmitting)
                }
            }
        }
    }

    private var downloaderBinding: Binding<String> {
        Binding(
            get: { viewState.selectedDownloaderID ?? "" },
            set: { onSelectDownloader($0) }
        )
    }

    private var savePathBinding: Binding<String> {
        Binding(
            get: { viewState.savePath },
            set: { onUpdateSavePath($0) }
        )
    }
}

struct SearchResultFilterSheetView: View {
    let viewState: SearchResultFilterSheetViewState
    let onSelectSite: (String?) -> Void
    let onSelectResolution: (String?) -> Void
    let onSelectQuality: (String?) -> Void
    let onSelectCodec: (String?) -> Void
    let onTogglePromotionOnly: (Bool) -> Void
    let onToggleHideHitAndRun: (Bool) -> Void
    let onSelectSortField: (SearchResultSortField) -> Void
    let onSelectSortOrder: (SearchResultSortOrder) -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("站点") {
                    filterOptionPicker(
                        title: "站点",
                        selection: siteSelection,
                        options: viewState.siteOptions,
                        allTitle: "全部站点"
                    )
                }

                Section("资源规格") {
                    filterOptionPicker(
                        title: "分辨率",
                        selection: resolutionSelection,
                        options: viewState.resolutionOptions,
                        allTitle: "全部分辨率"
                    )

                    filterOptionPicker(
                        title: "片源",
                        selection: qualitySelection,
                        options: viewState.qualityOptions,
                        allTitle: "全部片源"
                    )

                    filterOptionPicker(
                        title: "编码",
                        selection: codecSelection,
                        options: viewState.codecOptions,
                        allTitle: "全部编码"
                    )
                }

                Section("高级筛选") {
                    Toggle("仅显示促销资源", isOn: promotionOnlySelection)
                    Toggle("隐藏 H&R 资源", isOn: hideHitAndRunSelection)
                }

                Section("排序") {
                    Picker("排序依据", selection: sortFieldSelection) {
                        ForEach(SearchResultSortField.allCases) { field in
                            Text(field.title).tag(field)
                        }
                    }

                    Picker("排序方向", selection: sortOrderSelection) {
                        ForEach(SearchResultSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("筛选与排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }

                ToolbarItem(placement: .topBarLeading) {
                    if pendingFilterCount > 0 {
                        Button("重置", action: onReset)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("应用", action: onApply)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var pendingFilterCount: Int {
        var count = 0
        if viewState.selectedSiteName != nil { count += 1 }
        if viewState.selectedResolution != nil { count += 1 }
        if viewState.selectedQuality != nil { count += 1 }
        if viewState.selectedCodec != nil { count += 1 }
        if viewState.showPromotionOnly { count += 1 }
        if viewState.hideHitAndRun { count += 1 }
        if viewState.sortField != .relevance || viewState.sortOrder != .descending { count += 1 }
        return count
    }

    private var siteSelection: Binding<String?> {
        Binding(
            get: { viewState.selectedSiteName },
            set: { onSelectSite($0) }
        )
    }

    private var resolutionSelection: Binding<String?> {
        Binding(
            get: { viewState.selectedResolution },
            set: { onSelectResolution($0) }
        )
    }

    private var qualitySelection: Binding<String?> {
        Binding(
            get: { viewState.selectedQuality },
            set: { onSelectQuality($0) }
        )
    }

    private var codecSelection: Binding<String?> {
        Binding(
            get: { viewState.selectedCodec },
            set: { onSelectCodec($0) }
        )
    }

    private var promotionOnlySelection: Binding<Bool> {
        Binding(
            get: { viewState.showPromotionOnly },
            set: { onTogglePromotionOnly($0) }
        )
    }

    private var hideHitAndRunSelection: Binding<Bool> {
        Binding(
            get: { viewState.hideHitAndRun },
            set: { onToggleHideHitAndRun($0) }
        )
    }

    private var sortFieldSelection: Binding<SearchResultSortField> {
        Binding(
            get: { viewState.sortField },
            set: { onSelectSortField($0) }
        )
    }

    private var sortOrderSelection: Binding<SearchResultSortOrder> {
        Binding(
            get: { viewState.sortOrder },
            set: { onSelectSortOrder($0) }
        )
    }

    @ViewBuilder
    private func filterOptionPicker(
        title: String,
        selection: Binding<String?>,
        options: [SearchResultFilterOptionViewState],
        allTitle: String
    ) -> some View {
        Picker(title, selection: selection) {
            Text(allTitle).tag(Optional<String>.none)
            ForEach(options) { option in
                Text(option.title).tag(Optional(option.id))
            }
        }
    }
}
