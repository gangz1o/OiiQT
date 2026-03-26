import SwiftUI

struct MoviePilotDiscoveryView: View {
    @State private var viewModel = MoviePilotDiscoveryViewModel()
    @State private var navigationPath = NavigationPath()
    @Namespace private var heroTransition

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                categoryTabs
                    .moviePilotListRowInsets(top: 12, bottom: 8)

                if viewModel.viewState.sections.isEmpty {
                    emptyState
                        .moviePilotListRowInsets(top: 24, bottom: 32)
                } else {
                    ForEach(viewModel.viewState.sections) { section in
                        MediaSectionView(
                            viewState: section,
                            onTapMore: {
                                navigationPath.append(
                                    MoviePilotDiscoverySectionDestination(sectionID: section.id)
                                )
                            }
                        )
                            .moviePilotListRowInsets(top: 8, bottom: 16)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("发现")
            .searchable(text: $viewModel.searchText, prompt: "搜索 电影/剧集")
            .onSubmit(of: .search) {
                guard let destination = viewModel.makeMediaSearchDestination() else { return }
                navigationPath.append(destination)
            }
            .navigationDestination(for: String.self) { mediaID in
                MediaDetailView(
                    initialViewState: viewModel.makeMediaDetailBootstrapViewState(for: mediaID)
                )
                .navigationTransition(.zoom(sourceID: mediaID, in: heroTransition))
            }
            .navigationDestination(for: MoviePilotDiscoverySectionDestination.self) { destination in
                sectionListDestination(for: destination)
            }
            .navigationDestination(for: MoviePilotMediaSearchDestination.self) { destination in
                mediaSearchDestination(for: destination)
            }
            .task {
                await viewModel.loadDiscoveryData()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "没有匹配的内容",
            systemImage: "magnifyingglass",
            description: Text("试试其他关键词或分类。")
        )
        .frame(maxWidth: .infinity)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.viewState.categoryTabs, id: \.self) { category in
                    MoviePilotCategoryTabButton(
                        title: category,
                        isSelected: viewModel.viewState.selectedCategory == category
                    ) {
                        viewModel.selectCategory(category)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func sectionListDestination(for destination: MoviePilotDiscoverySectionDestination) -> some View {
        if let bootstrap = viewModel.makeSectionListBootstrapState(for: destination.sectionID) {
            MoviePilotSectionListView(bootstrap: bootstrap)
        } else {
            ContentUnavailableView(
                "无法打开列表",
                systemImage: "film.stack",
                description: Text("当前分区暂时不可用。")
            )
        }
    }

    @ViewBuilder
    private func mediaSearchDestination(for destination: MoviePilotMediaSearchDestination) -> some View {
        if let bootstrap = viewModel.makeMediaSearchBootstrapState(for: destination.query) {
            MoviePilotMediaSearchView(bootstrap: bootstrap)
        } else {
            ContentUnavailableView(
                "无法执行搜索",
                systemImage: "magnifyingglass.circle",
                description: Text("请先配置可用的 MoviePilot 服务器。")
            )
        }
    }
}

private extension View {
    func moviePilotListRowInsets(top: CGFloat, bottom: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct MoviePilotSectionListView: View {
    @State private var viewModel: MoviePilotSectionListViewModel
    @Namespace private var heroTransition

    init(bootstrap: MoviePilotSectionListBootstrapState) {
        _viewModel = State(wrappedValue: MoviePilotSectionListViewModel(bootstrap: bootstrap))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.viewState.items.isEmpty {
                    if viewModel.viewState.isInitialLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ContentUnavailableView(
                            "暂无内容",
                            systemImage: "film",
                            description: Text("稍后重试或下拉刷新。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    MoviePilotSectionPosterGridView(items: viewModel.viewState.items)
                        .equatable()

                    if viewModel.viewState.canLoadMore || viewModel.viewState.isLoadingMore {
                        MoviePilotSectionListLoadMoreView(isLoading: viewModel.viewState.isLoadingMore)
                            .id(viewModel.viewState.paginationTrigger)
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPageIfNeeded()
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.viewState.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MoviePilotSectionListMediaDestination.self) { destination in
            MediaDetailView(
                initialViewState: viewModel.makeMediaDetailBootstrapViewState(for: destination.mediaID)
            )
            .navigationTransition(.zoom(sourceID: destination.mediaID, in: heroTransition))
        }
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.loadInitialPageIfNeeded()
        }
    }
}

private struct MoviePilotSectionPosterGridView: View, Equatable {
    private static let idealPosterWidth: CGFloat = 118
    private static let minimumColumnCount = 2
    private static let maximumColumnCount = 6
    private static let gridSpacing: CGFloat = 12

    @State private var availableWidth: CGFloat = 0
    @Namespace private var heroTransition
    let items: [MediaCardViewState]

    static func == (lhs: MoviePilotSectionPosterGridView, rhs: MoviePilotSectionPosterGridView) -> Bool {
        lhs.items == rhs.items
    }

    var body: some View {
        let metrics = Self.metrics(for: availableWidth)

        LazyVGrid(columns: metrics.columns, alignment: .center, spacing: Self.gridSpacing) {
            ForEach(items) { item in
                NavigationLink(value: MoviePilotSectionListMediaDestination(mediaID: item.id)) {
                    MediaCardView(viewState: item, layout: metrics.layout)
                }
                .matchedTransitionSource(id: item.id, in: heroTransition)
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    floor(proxy.size.width)
                } action: { newWidth in
                    guard newWidth > 0, newWidth != availableWidth else { return }
                    availableWidth = newWidth
                }
        }
    }

    private static func metrics(for availableWidth: CGFloat) -> GridMetrics {
        let fallbackWidth = MediaCardLayout.strip.width * CGFloat(minimumColumnCount)
            + gridSpacing * CGFloat(minimumColumnCount - 1)
        let width = max(availableWidth, fallbackWidth)
        let rawColumnCount = Int((width + gridSpacing) / (idealPosterWidth + gridSpacing))
        let columnCount = min(max(rawColumnCount, minimumColumnCount), maximumColumnCount)
        let totalSpacing = CGFloat(columnCount - 1) * gridSpacing
        let posterWidth = floor((width - totalSpacing) / CGFloat(columnCount))
        let columns = Array(
            repeating: GridItem(.fixed(posterWidth), spacing: gridSpacing, alignment: .top),
            count: columnCount
        )

        return GridMetrics(columns: columns, layout: MediaCardLayout(width: posterWidth))
    }

    private struct GridMetrics {
        let columns: [GridItem]
        let layout: MediaCardLayout
    }
}

private struct MoviePilotMediaSearchView: View {
    @State private var viewModel: MoviePilotMediaSearchViewModel
    @Namespace private var heroTransition

    init(bootstrap: MoviePilotMediaSearchBootstrapState) {
        _viewModel = State(wrappedValue: MoviePilotMediaSearchViewModel(bootstrap: bootstrap))
    }

    var body: some View {
        List {
            if viewModel.viewState.items.isEmpty {
                searchEmptyState
                    .moviePilotListRowInsets(top: 24, bottom: 32)
            } else {
                ForEach(viewModel.viewState.items) { item in
                    NavigationLink(value: MoviePilotSectionListMediaDestination(mediaID: item.id)) {
                        MoviePilotSectionListRowView(viewState: item)
                    }
                    .buttonStyle(.plain)
                    .moviePilotListRowInsets(top: 8, bottom: 8)
                }

                if viewModel.viewState.canLoadMore || viewModel.viewState.isLoadingMore {
                    MoviePilotSectionListLoadMoreView(isLoading: viewModel.viewState.isLoadingMore)
                        .id(viewModel.viewState.paginationTrigger)
                        .moviePilotListRowInsets(top: 12, bottom: 24)
                        .onAppear {
                            Task {
                                await viewModel.loadNextPageIfNeeded()
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.viewState.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(viewModel.viewState.title)
                        .font(.headline)
                    Text(viewModel.viewState.query)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .navigationDestination(for: MoviePilotSectionListMediaDestination.self) { destination in
            MediaDetailView(
                initialViewState: viewModel.makeMediaDetailBootstrapViewState(for: destination.mediaID)
            )
            .navigationTransition(.zoom(sourceID: destination.mediaID, in: heroTransition))
        }
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.loadInitialPageIfNeeded()
        }
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        if viewModel.viewState.isInitialLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let errorMessage = viewModel.viewState.errorMessage, !errorMessage.isEmpty {
            ContentUnavailableView(
                "搜索失败",
                systemImage: "wifi.exclamationmark",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView.search(text: viewModel.viewState.query)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct MoviePilotSectionListRowView: View {
    let viewState: MediaCardViewState

    var body: some View {
        MoviePilotSectionListRowContentView(viewState: viewState)
            .equatable()
    }
}

private struct MoviePilotSectionListRowContentView: View, Equatable {
    static let posterWidth: CGFloat = 72
    static let posterHeight: CGFloat = 108
    static let posterSize = CGSize(width: posterWidth, height: posterHeight)

    let viewState: MediaCardViewState

    static func == (lhs: MoviePilotSectionListRowContentView, rhs: MoviePilotSectionListRowContentView) -> Bool {
        lhs.viewState == rhs.viewState
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SimpleCachedImage(
                url: URL(string: viewState.posterURLString),
                downsampleSize: Self.posterSize,
                cacheOriginal: false
            )
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.posterWidth, height: Self.posterHeight)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(viewState.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if !viewState.ratingText.isEmpty {
                        Label(viewState.ratingText, systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                    }

                    Text(viewState.isSeries ? "剧集" : "电影")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text("查看详情")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 18))
    }
}

private struct MoviePilotSectionListLoadMoreView: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text(isLoading ? "正在加载更多" : "加载更多")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MoviePilotCategoryTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.pink : Color(.secondarySystemBackground))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(isSelected ? Color.pink.opacity(0.2) : Color.black.opacity(0.05), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MoviePilotDiscoveryView()
}
