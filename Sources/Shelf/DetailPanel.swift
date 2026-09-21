import SwiftUI
import AppKit

struct DetailPanel: View {
    @EnvironmentObject var store: ShelfStore
    @ObservedObject private var settings = ShelfSettings.shared
    @Binding var selection: Set<UUID>

    @FocusState private var noteFocused: Bool
    @State private var noteDraft: String = ""
    @State private var pathCopied = false

    private var selectedItems: [ShelfItem] {
        store.items.filter { selection.contains($0.id) }
    }

    private var single: ShelfItem? {
        selectedItems.count == 1 ? selectedItems[0] : nil
    }

    var body: some View {
        Group {
            if selectedItems.isEmpty {
                placeholder
            } else if let item = single {
                singleDetail(item)
            } else {
                multiDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: selection) {
            noteDraft = single?.note ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .shelfFocusNote)) { _ in
            noteDraft = single?.note ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { noteFocused = true }
        }
    }

    // MARK: 占位

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "cursorarrow.click")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary.opacity(0.7))
            Text("选中一个文件查看详情")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("双击可直接打开原文件")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: 单个文件

    private func singleDetail(_ item: ShelfItem) -> some View {
        let module = store.module(with: item.moduleID)
        let accent = module?.accent ?? .accentColor
        let url = item.resolvedURL()

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(item: item, module: module, accent: accent, url: url)
                actions(item: item, accent: accent, url: url)

                ShelfDivider()

                InfoRow(title: "原文件位置", icon: "folder") {
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.displayPath)
                            .font(.system(size: 10.5))
                            .foregroundStyle(url == nil ? .red : .secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        if url != nil {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url?.path ?? "", forType: .string)
                                pathCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    pathCopied = false
                                }
                            } label: {
                                Image(systemName: pathCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(pathCopied ? Color.green : .secondary)
                            }
                            .buttonStyle(PressChipStyle())
                            .help("复制完整路径")
                        }
                    }
                }

                InfoRow(title: "加入时间", icon: "clock") {
                    Text(item.dateAdded.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                if let opened = item.dateOpened {
                    InfoRow(title: "上次打开", icon: "clock.arrow.circlepath") {
                        Text(opened.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                ShelfDivider()

                noteSection(item: item, accent: accent)
                tagSection(item: item)

                Spacer(minLength: 8)

                Button {
                    selection.remove(item.id)
                    store.removeItem(item.id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash").font(.system(size: 10))
                        Text("从模块中移除").font(.system(size: 11.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.red.opacity(0.1))
                    )
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("只移除快捷方式，原文件不受影响")
            }
            .padding(14)
        }
    }

    private func header(item: ShelfItem, module: ShelfModule?, accent: Color, url: URL?) -> some View {
        HStack(alignment: .top, spacing: 11) {
            if let url {
                FileIconView(url: url, size: 40)
            } else {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let m = module {
                    HStack(spacing: 4) {
                        Image(systemName: m.symbol).font(.system(size: 8))
                        Text(m.name).font(.system(size: 10))
                    }
                    .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func actions(item: ShelfItem, accent: Color, url: URL?) -> some View {
        VStack(spacing: 6) {
            WideButton(title: "在 Finder 中显示", symbol: "folder", color: accent, prominent: true) {
                if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            .disabled(url == nil)

            HStack(spacing: 6) {
                WideButton(title: "打开", symbol: "arrow.up.forward.square", color: accent) {
                    if let url {
                        store.markOpened(item.id)
                        NSWorkspace.shared.open(url)
                    }
                }
                .disabled(url == nil)

                Menu {
                    ForEach(store.modules.filter { $0.id != item.moduleID }) { m in
                        Button(m.name) { store.moveItem(item.id, to: m.id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.doc.on.clipboard").font(.system(size: 10))
                        Text("移动").font(.system(size: 11.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .menuStyle(.borderlessButton)
                .frame(width: 86)
            }
        }
    }

    private func noteSection(item: ShelfItem, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("备注")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("例如：期中考范围、待打印…", text: $noteDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .lineLimit(2...4)
                .focused($noteFocused)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(noteFocused ? accent.opacity(0.7) : settings.appBorder,
                                      lineWidth: 1)
                )
                .onChange(of: noteDraft) { oldValue, newValue in
                    var i = item
                    i.note = newValue
                    store.updateItem(i)
                }
        }
    }

    private func tagSection(item: ShelfItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("彩色标签")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(ShelfTag.pickable) { t in
                    Button {
                        var i = item
                        i.tagRaw = (item.tag == t) ? ShelfTag.none.rawValue : t.rawValue
                        store.updateItem(i)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(t.color)
                                .frame(width: 19, height: 19)
                                .shadow(color: t.color.opacity(0.5),
                                        radius: item.tag == t ? 5 : 0, y: 1)
                            if item.tag == t {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 23, height: 23)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.2)
                                .frame(width: 23, height: 23)
                                .opacity(item.tag == t ? 1 : 0)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(t.label)
                }
            }
        }
    }

    // MARK: 多选

    private var multiDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text("已选中 \(selectedItems.count) 个文件")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            Text("批量设置标签")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(ShelfTag.pickable) { t in
                    Button {
                        for item in selectedItems {
                            var i = item
                            i.tagRaw = t.rawValue
                            store.updateItem(i)
                        }
                    } label: {
                        Circle().fill(t.color).frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("全部标为\(t.label)")
                }
            }

            ShelfDivider()

            Button {
                let ids = selection
                selection = []
                store.removeItems(ids)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash").font(.system(size: 10))
                    Text("移除这 \(selectedItems.count) 项").font(.system(size: 11.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                )
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(14)
    }
}
