import SwiftUI

struct MediaDetailView: View {
    @State private var viewModel: MediaDetailViewModel

    init(initialViewState: MediaDetailViewState) {
        _viewModel = State(wrappedValue: MediaDetailViewModel(initialViewState: initialViewState))
    }

    var body: some View {
        ZStack {
            // ── 层1：全屏海报模糊背景 ──────────────────────────────────
            posterBackground

            // ── 层2：内容 ScrollView（透明直通背景） ──────────────────
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    posterHeroSection      // Banner + 标题文字 + 简介 + 按钮
                    actorsSection
                    searchResultsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(viewModel.viewState.title.isEmpty ? "详情" : viewModel.viewState.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .task(id: viewModel.viewState.id) {
            await viewModel.loadDetail(id: viewModel.viewState.id)
        }
        .sheet(item: searchFilterSheetBinding) { sheetViewState in
            SearchResultFilterSheetView(
                viewState: viewModel.searchFilterSheetViewState ?? sheetViewState,
                onSelectSite: { viewModel.updateSearchFilterSite($0) },
                onSelectResolution: { viewModel.updateSearchFilterResolution($0) },
                onSelectQuality: { viewModel.updateSearchFilterQuality($0) },
                onSelectCodec: { viewModel.updateSearchFilterCodec($0) },
                onTogglePromotionOnly: { viewModel.updateSearchFilterPromotionOnly($0) },
                onToggleHideHitAndRun: { viewModel.updateSearchFilterHideHitAndRun($0) },
                onSelectSortField: { viewModel.updateSearchFilterSortField($0) },
                onSelectSortOrder: { viewModel.updateSearchFilterSortOrder($0) },
                onReset: { viewModel.resetSearchFilterSheet() },
                onCancel: { viewModel.cancelSearchFilterSheet() },
                onApply: { viewModel.applySearchFilterSheet() }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.showSubscribeSheet },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissSubscribeSheet()
                    }
                }
            )
        ) {
            if let form = viewModel.subscribeFormViewState {
                SubscribeSettingsSheetView(
                    viewState: form,
                    onSelectOption: { fieldID, optionID in
                        viewModel.updateSubscribeOption(fieldID: fieldID, optionID: optionID)
                    },
                    onUpdateText: { fieldID, text in
                        viewModel.updateSubscribeText(fieldID: fieldID, text: text)
                    },
                    onToggle: { fieldID, isOn in
                        viewModel.updateSubscribeToggle(fieldID: fieldID, isOn: isOn)
                    },
                    onCancel: {
                        viewModel.dismissSubscribeSheet()
                    },
                    onSubmit: {
                        await viewModel.submitSubscription(form: viewModel.subscribeFormViewState)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(
            item: Binding(
                get: { viewModel.downloadFormViewState },
                set: { newValue in
                    if newValue == nil {
                        viewModel.cancelDownload()
                    }
                }
            )
        ) { _ in
            if let form = viewModel.downloadFormViewState {
                DownloadConfigurationSheetView(
                    viewState: form,
                    onSelectDownloader: { viewModel.updateDownloadFormDownloader($0) },
                    onUpdateSavePath: { viewModel.updateDownloadFormSavePath($0) },
                    onCancel: { viewModel.cancelDownload() },
                    onConfirm: { await viewModel.confirmDownload() }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var searchFilterSheetBinding: Binding<SearchResultFilterSheetViewState?> {
        Binding(
            get: { viewModel.searchFilterSheetViewState },
            set: { newValue in
                guard newValue == nil else { return }
                viewModel.applySearchFilterSheet()
            }
        )
    }

    // MARK: - Background

    /// 层1：海报铺满全屏，极强模糊 + ultraThinMaterial 遮罩
    /// Material 自动适配浅色/深色模式，保留海报色调渗透感
    private var posterBackground: some View {
        GeometryReader { geo in
            SimpleCachedImage(
                url: URL(string: viewModel.viewState.posterURLString),
                downsampleSize: CGSize(width: 400, height: 600)
            )
            .aspectRatio(contentMode: .fill)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .blur(radius: 48, opaque: true)   // opaque: true 防止边缘透白
            .overlay(.ultraThinMaterial)       // 自动适配浅色/深色
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero Banner Section

    /// 流媒体风格：全宽海报当剧照 + 底部渐变遮罩 + 标题文字压底
    private var posterHeroSection: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── 全宽 Banner 图（突破内边距铺满屏幕）────────────────────
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {

                    // 剧照优先，无剧照则 fallback 海报
                    let bannerURL = viewModel.viewState.backdropURLString.isEmpty
                        ? viewModel.viewState.posterURLString
                        : viewModel.viewState.backdropURLString
                    SimpleCachedImage(
                        url: URL(string: bannerURL),
                        downsampleSize: CGSize(width: geo.size.width, height: geo.size.height)
                    )
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                    // 三段渐变遮罩：顶部透明 → 中部 → 底部深黑
                    LinearGradient(
                        stops: [
                            .init(color: .clear,               location: 0.0),
                            .init(color: .black.opacity(0.45),  location: 0.55),
                            .init(color: .black.opacity(0.88),  location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // 标题 + 元数据压在图片左下角（白色文字）
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.viewState.title.isEmpty ? "正在载入..." : viewModel.viewState.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

                        HStack(spacing: 6) {
                            // 类型
                            Text(viewModel.viewState.isSeries ? "剧集" : "电影")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule(style: .continuous).fill(.white.opacity(0.2)))

                            // 评分
                            if !viewModel.viewState.ratingText.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.yellow)
                                    Text(viewModel.viewState.ratingText)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule(style: .continuous).fill(.white.opacity(0.2)))
                            }

                            // 已订阅徽章
                            if viewModel.viewState.isSubscribed {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text("已订阅")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule(style: .continuous).fill(.tint.opacity(0.75)))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }
            }
            // Banner 高度：屏宽 × 0.58 ≈ Apple TV+ / Netflix 展示比
            .frame(height: UIScreen.main.bounds.width * 0.58)
            // 突破 LazyVStack 的横向 padding，边到边铺满
            .padding(.horizontal, -16)

            // ── 无缝衔接渐变（消除 banner 底部硬边）────────────────────
            // 从深色延续渐变到透明，与上面的遮罩颜色吻合
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.50), location: 0.0),
                    .init(color: .clear,               location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .padding(.horizontal, -16)
            .offset(y: -40)             // 上移覆盖 banner 底部，不占用额外高度
            .padding(.bottom, -40)      // 补回 offset 占据的空间

            // ── 简介 + 按钮（Banner 下方正常内容流）──────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("简介")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.top, 20)

                if viewModel.viewState.isOverviewLoading {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0 ..< 3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.secondary.opacity(0.18))
                                .frame(maxWidth: i == 2 ? 200 : .infinity)
                                .frame(height: 13)
                        }
                    }
                    .redacted(reason: .placeholder)
                } else {
                    Text(viewModel.viewState.overviewText ?? "暂无简介")
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.viewState.isOverviewLoading || viewModel.viewState.isActorsLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在同步详情")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }

                // 操作按钮
                HStack(spacing: 12) {
                    Button { viewModel.intentSearch() } label: {
                        Group {
                            if viewModel.viewState.isSearchLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("搜索", systemImage: "magnifyingglass")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.indigo)
                    .disabled(viewModel.viewState.isSearchLoading)

                    Button { viewModel.intentSubscribe() } label: {
                        Group {
                            if viewModel.viewState.isSubscribeLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(
                                    viewModel.viewState.isSubscribed ? "已订阅" : "订阅",
                                    systemImage: viewModel.viewState.isSubscribed
                                        ? "checkmark.circle.fill" : "bell.fill"
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(viewModel.viewState.isSubscribed ? .teal : .green)
                    .disabled(viewModel.viewState.isSubscribeLoading)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actors Section

    private var actorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "演员表")

            if viewModel.viewState.isActorsLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0 ..< 5, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 10) {
                                Circle()
                                    .fill(.secondary.opacity(0.18))
                                    .frame(width: 72, height: 72)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.secondary.opacity(0.18))
                                    .frame(width: 72, height: 12)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.secondary.opacity(0.18))
                                    .frame(width: 54, height: 10)
                            }
                            .redacted(reason: .placeholder)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            } else if viewModel.viewState.actors.isEmpty {
                ContentUnavailableView(
                    "暂无演员信息",
                    systemImage: "person.2.slash",
                    description: Text("当前媒体没有返回可展示的演员表。")
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(viewModel.viewState.actors) { actor in
                            MediaActorCardView(viewState: actor)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Search Results Section

    @ViewBuilder
    private var searchResultsSection: some View {
        let filteredResults = viewModel.filteredSearchResults
        let hasRawResults = !viewModel.viewState.searchResults.isEmpty

        if viewModel.viewState.isSearchLoading
            || hasRawResults
            || viewModel.viewState.searchFeedbackText != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionHeader(title: "搜索结果")

                    Spacer(minLength: 12)

                    if hasRawResults {
                        Button {
                            viewModel.presentSearchFilterSheet()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.caption.weight(.semibold))
                                Text("筛选与排序")
                                    .font(.footnote.weight(.semibold))
                                if viewModel.activeSearchFilterCount > 0 {
                                    Text("\(viewModel.activeSearchFilterCount)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(.tint)
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let feedback = viewModel.viewState.searchFeedbackText, !feedback.isEmpty {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if viewModel.viewState.isSearchLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在检索站点资源")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                } else if viewModel.viewState.searchResults.isEmpty {
                    ContentUnavailableView(
                        "还没有资源结果",
                        systemImage: "magnifyingglass.circle",
                        description: Text(viewModel.viewState.searchFeedbackText ?? "点击下方搜索按钮后会显示结果。")
                    )
                } else if filteredResults.isEmpty {
                    ContentUnavailableView(
                        "没有符合条件的资源",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("调整筛选条件后再试。")
                    )
                } else {
                    SearchResultListView(
                        results: filteredResults,
                        onTapResult: { resultID in
                            Task { await viewModel.prepareDownloadForm(for: resultID) }
                        }
                    )
                    .equatable()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

private struct MediaActorCardView: View {
    let viewState: ActorViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SimpleCachedImage(
                url: URL(string: viewState.profileURLString),
                downsampleSize: CGSize(width: 144, height: 144)
            )
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 72, height: 72)
            .background(SeedPilotPlaceholder())
            .clipShape(Circle())

            Text(viewState.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(viewState.characterName.isEmpty ? "演员" : viewState.characterName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 90, alignment: .leading)
    }
}

private struct SearchResultListView: View, Equatable {
    let results: [SearchResultViewState]
    let onTapResult: (String) -> Void

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(results) { result in
                SearchResultRowView(viewState: result)
                    .equatable()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTapResult(result.id)
                    }
                    .contextMenu {
                        if let pageURL = URL(string: result.pageURLString), !result.pageURLString.isEmpty {
                            Link(destination: pageURL) {
                                Label("在浏览器中打开", systemImage: "safari")
                            }
                        }
                    }
            }
        }
    }

    static func == (lhs: SearchResultListView, rhs: SearchResultListView) -> Bool {
        lhs.results == rhs.results
    }
}

private struct SearchResultRowView: View, Equatable {
    let viewState: SearchResultViewState

    static func == (lhs: SearchResultRowView, rhs: SearchResultRowView) -> Bool {
        lhs.viewState == rhs.viewState
    }

    var body: some View {
        rowBody
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
    }

    private var rowBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            // ── 第一行：站点名 + 促销标签 + 做种数 + 文件大小 ──
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewState.siteName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let promotionTag = viewState.promotionTag,
                   let promotionPalette = viewState.promotionPalette {
                    Text(promotionTag)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(searchResultHex: promotionPalette.foregroundHex))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(searchResultHex: promotionPalette.backgroundHex))
                        )
                }

                Spacer(minLength: 6)

                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                    Text(viewState.seedersCount.formatted(.number.grouping(.automatic)))
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.64, blue: 0.31))

                Text(viewState.sizeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // ── 第二行：主标题 + 副标题 ──
            Text(viewState.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !viewState.subtitle.isEmpty {
                Text(viewState.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // ── 第三行：标签栏 ──
            if !viewState.badges.isEmpty {
                SearchResultBadgeStripView(badges: viewState.badges)
                    .equatable()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var accessibilityLabel: String {
        var components = [
            viewState.siteName,
            "做种 \(viewState.seedersCount)",
            viewState.title,
            viewState.subtitle,
            viewState.sizeString
        ]

        if let promotionTag = viewState.promotionTag {
            components.append("促销 \(promotionTag)")
        }

        if !viewState.badges.isEmpty {
            components.append(viewState.badges.map(\.text).joined(separator: "、"))
        }

        return components.filter { !$0.isEmpty }.joined(separator: "，")
    }
}

// MARK: - Download Configuration Sheet

private struct DownloadConfigurationSheetView: View {
    let viewState: DownloadFormViewState
    let onSelectDownloader: (String) -> Void
    let onUpdateSavePath: (String) -> Void
    let onCancel: () -> Void
    let onConfirm: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                // Resource info
                Section {
                    Text(viewState.resourceTitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                } header: {
                    Text("资源")
                }

                // Downloader selection
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

                // Save path (optional)
                Section {
                    TextField("留空使用默认路径", text: savePathBinding)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("保存路径")
                } footer: {
                    Text("可选。留空将使用 MoviePilot 默认配置的保存路径。")
                }

                // Error message
                if let error = viewState.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
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
                        Task { await onConfirm() }
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

private struct SearchResultBadgeStripView: View, Equatable {
    let badges: [SearchResultBadgeViewState]

    static func == (lhs: SearchResultBadgeStripView, rhs: SearchResultBadgeStripView) -> Bool {
        lhs.badges == rhs.badges
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(badges) { badge in
                    Text(badge.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(searchResultHex: badge.palette.foregroundHex))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(searchResultHex: badge.palette.backgroundHex))
                        )
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct SearchResultFilterSheetView: View {
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

private extension Color {
    init(searchResultHex hex: String) {
        let sanitizedHex = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitizedHex).scanHexInt64(&value)

        let red, green, blue, alpha: Double
        switch sanitizedHex.count {
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        default:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
