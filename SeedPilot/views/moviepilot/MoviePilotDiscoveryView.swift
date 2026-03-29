import SwiftUI

struct MoviePilotDiscoveryView: View {
    @State private var viewModel = MoviePilotDiscoveryViewModel()
    @State private var serverStore = MoviePilotServerStore.shared
    @State private var navigationPath = NavigationPath()

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
            .navigationTitle(moviePilotLocalized("发现"))
            .searchable(text: $viewModel.searchText, prompt: moviePilotLocalized("搜索 电影/剧集"))
            .onSubmit(of: .search) {
                guard let destination = viewModel.makeMediaSearchDestination() else { return }
                navigationPath.append(destination)
            }
            .navigationDestination(for: String.self) { mediaID in
                MediaDetailView(
                    initialViewState: viewModel.makeMediaDetailBootstrapViewState(for: mediaID)
                )
            }
            .navigationDestination(for: MoviePilotDiscoverySectionDestination.self) { destination in
                sectionListDestination(for: destination)
            }
            .navigationDestination(for: MoviePilotMediaSearchDestination.self) { destination in
                mediaSearchDestination(for: destination)
            }
            .task(id: serverStore.activeServerID) {
                navigationPath = NavigationPath()
                await viewModel.loadDiscoveryData()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            moviePilotLocalized("没有匹配的内容"),
            systemImage: "magnifyingglass",
            description: Text(moviePilotLocalized("试试其他关键词或分类。"))
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
                moviePilotLocalized("无法打开列表"),
                systemImage: "film.stack",
                description: Text(moviePilotLocalized("当前分区暂时不可用。"))
            )
        }
    }

    @ViewBuilder
    private func mediaSearchDestination(for destination: MoviePilotMediaSearchDestination) -> some View {
        if let bootstrap = viewModel.makeMediaSearchBootstrapState(for: destination.query) {
            MoviePilotMediaSearchView(bootstrap: bootstrap)
        } else {
            ContentUnavailableView(
                moviePilotLocalized("无法执行搜索"),
                systemImage: "magnifyingglass.circle",
                description: Text(moviePilotLocalized("请先配置可用的 MoviePilot 服务器。"))
            )
        }
    }
}

private struct MoviePilotCategoryTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(moviePilotLocalized(title))
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
