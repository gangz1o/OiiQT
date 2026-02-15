//
//  AddTorrentView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//
import SwiftUI
import UniformTypeIdentifiers

struct AddTorrentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appStateManager

    // Mode
    enum InputMode: String, CaseIterable {
        case link = "链接"
        case file = "文件"
    }
    @State private var inputMode: InputMode = .link

    // Inputs
    @State private var magnetLinks: String = ""
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String = ""

    // Options
    @State private var options = AddTorrentOptions()
    @State private var tagsString: String = "" // For binding to comma-separated text

    // State
    @State private var isAdding = false
    @State private var showFileImporter = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Input Mode
                Section {
                    Picker("添加方式", selection: $inputMode) {
                        ForEach(InputMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .padding()
                }

                // Section 2: Content
                Section {
                    if inputMode == .link {
                        TextEditor(text: $magnetLinks)
                            .frame(minHeight: 120)
                            .overlay(
                                Group {
                                    if magnetLinks.isEmpty {
                                        Text("在此粘贴磁力链接、HTTP/HTTPS 链接，每行一个")
                                            .foregroundColor(.gray.opacity(0.6))
                                            .padding(.top, 8)
                                            .padding(.leading, 4)
                                    }
                                },
                                alignment: .topLeading
                            )
                    } else {
                        Button {
                            showFileImporter = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text(selectedFileName.isEmpty ? "选择 .torrent 文件" : selectedFileName)
                                        .foregroundStyle(selectedFileName.isEmpty ? .primary : .primary)
                                    if !selectedFileName.isEmpty {
                                        Text("点击更换")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } header: {
                    Text(inputMode == .link ? "链接列表" : "种子文件")
                }

                // Section 3: Options
                Section("配置") {
                    HStack {
                        Text("保存路径")
                        Spacer()
                        TextField("默认", text: $options.savePath)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        Text("分类")
                        Spacer()
                        TextField("可选", text: $options.category)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        Text("标签")
                        Spacer()
                         TextField("用逗号分隔", text: $tagsString)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: tagsString) { oldValue, newValue in
                                options.tags = newValue.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                            }
                    }
                }

                // Section 4: Flags
                Section {
                    Toggle("自动开始任务", isOn: Binding(
                        get: { !options.isPaused },
                        set: { options.isPaused = !$0 }
                    ))

                    Toggle("跳过哈希校验", isOn: $options.skipHashCheck)

                    Toggle("顺序下载", isOn: $options.isSequential)
                } header: {
                    Text("状态")
                }
            }
            .navigationTitle("添加任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addTasks()
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            Text("添加")
                                .bold()
                        }
                    }
                    .disabled(isAdding || (inputMode == .link && magnetLinks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || (inputMode == .file && selectedFileURL == nil))
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item], // UTType.item includes roughly everything, verifying extension manually is safer or use .data
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // Security Note: In SwiftUI fileImporter, we usually get security scoped URL.
                    // We must prepare to access it.
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        // Copy to tmp or read data immediately?
                        // Better to keep URL and read on submit, but we need to ensure access persists or just read metadata now.
                        selectedFileName = url.lastPathComponent
                        // We will store the URL but we might need to handle security scope again when reading.
                        // Actually, for simplicity, let's copy it to a temp location we control.
                        do {
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                            try? FileManager.default.removeItem(at: tempURL)
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            selectedFileURL = tempURL
                        } catch {
                            print("File copy error: \(error)")
                            errorMessage = "读取文件失败: \(error.localizedDescription)"
                            showError = true
                        }
                    } else {
                        // Access denied
                        errorMessage = "无法访问选中的文件"
                        showError = true
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func addTasks() {
        isAdding = true

        Task {
            do {
                if inputMode == .link {
                    // Split by newlines and filter valid links
                    let links = magnetLinks.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    if !links.isEmpty {
                        // qBittorrent API 'urls' parameter accepts both magnet: and http:// links
                        // mixed in the same request (separated by \n), so we can send them all at once.
                        try await appStateManager.addTorrents(links, options: options)
                    }
                } else if let url = selectedFileURL {
                    try await appStateManager.addTorrentFile(url, options: options)
                }

                await MainActor.run {
                    isAdding = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAdding = false
                    errorMessage = "添加失败: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

#Preview {
    AddTorrentView()
        .environment(AppStateManager())
}
