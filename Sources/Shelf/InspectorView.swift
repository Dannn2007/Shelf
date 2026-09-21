import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let shelfFocusNote = Notification.Name("ShelfFocusNoteEditor")
}

// MARK: - 右侧面板

struct InspectorView: View {
    @EnvironmentObject var store: ShelfStore
    @ObservedObject var settings: ShelfSettings
    @Binding var selection: Set<UUID>

    @State private var queue: [URL] = []
    @State private var pending: ClassificationResult?
    @State private var isTargeted = false
    @State private var rememberRule = true
    @State private var aiTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ClassifyDropPanel(pending: $pending,
                              queueCount: queue.count,
                              isTargeted: isTargeted,
                              rememberRule: $rememberRule,
                              onCommit: commit,
                              onSkip: advance)
                .frame(minHeight: 176)
                .frame(maxHeight: pending == nil ? 210 : 430)

            ShelfDivider()

            DetailPanel(selection: $selection)
        }
        .background(settings.appBackground)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.easeOut(duration: 0.16), value: isTargeted)
    }

    // MARK: 拖放

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                else if let s = item as? String { url = URL(string: s) }
                guard let url else { return }
                DispatchQueue.main.async {
                    queue.append(url)
                    if pending == nil { advance() }
                }
            }
        }
        return handled
    }

    // MARK: 分类流程

    @MainActor
    private func advance() {
        aiTask?.cancel()
        if queue.isEmpty {
            pending = nil
            return
        }
        let url = queue.removeFirst()
        let fp = FileFingerprint(url: url)

        var foldersByModule: [UUID: Set<String>] = [:]
        for m in store.modules {
            foldersByModule[m.id] = Set(
                store.items.filter { $0.moduleID == m.id }.compactMap { $0.containingFolder?.path }
            )
        }
        let cands = RuleEngine.classify(fp,
                                        modules: store.modules,
                                        rules: store.rules,
                                        existingFoldersByModule: foldersByModule)
        pending = ClassificationResult(fingerprint: fp, candidates: cands)

        if settings.aiEnabled, !settings.aiAPIKey.isEmpty {
            aiTask = Task { await runAI(for: fp) }
        }
    }

    @MainActor
    private func runAI(for fp: FileFingerprint) async {
        guard pending?.fingerprint.url == fp.url else { return }
        pending?.aiState = .loading

        let modules = store.modules
        let apiKey = settings.aiAPIKey
        let model = settings.aiModel
        let base = settings.aiBaseURL

        do {
            let s = try await AIClassifier.suggest(fp: fp, modules: modules,
                                                   apiKey: apiKey, model: model, baseURL: base)
            guard !Task.isCancelled, pending?.fingerprint.url == fp.url else { return }

            let byName = Dictionary(modules.map { ($0.name.lowercased(), $0) },
                                    uniquingKeysWith: { a, _ in a })
            var merged: [ClassificationCandidate] = []

            func append(_ m: ShelfModule, conf: Int, reason: String) {
                guard !merged.contains(where: { $0.moduleID == m.id }) else { return }
                merged.append(ClassificationCandidate(
                    moduleID: m.id, moduleName: m.name, accentHex: m.accentHex, symbol: m.symbol,
                    confidence: conf,
                    reasons: reason.isEmpty ? [] : [reason],
                    source: .ai))
            }

            if let m = byName[s.primaryName.lowercased()] { append(m, conf: 92, reason: s.reason) }
            for n in s.alternateNames {
                if let m = byName[n.lowercased()] { append(m, conf: 64, reason: "AI 备选") }
            }
            for c in (pending?.candidates ?? []) where !merged.contains(where: { $0.moduleID == c.moduleID }) {
                merged.append(c)
            }

            pending?.candidates = Array(merged.prefix(4))
            pending?.aiNote = s.reason
            pending?.aiState = .done
        } catch {
            guard !Task.isCancelled else { return }
            pending?.aiState = .failed
        }
    }

    @MainActor
    private func commit(_ moduleID: UUID) {
        guard let r = pending else { return }
        store.addItem(url: r.fingerprint.url, to: moduleID)
        if rememberRule {
            let token = RuleEngine.representativeToken(for: r.fingerprint)
            store.learn(token: token, moduleID: moduleID)
        }
        advance()
    }
}

// MARK: - 分类投放面板

private struct ClassifyDropPanel: View {
    @EnvironmentObject var store: ShelfStore
    @ObservedObject private var settings = ShelfSettings.shared
    @Binding var pending: ClassificationResult?
    let queueCount: Int
    let isTargeted: Bool
    @Binding var rememberRule: Bool
    let onCommit: (UUID) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .fill(Color.accentColor.opacity(0.13))
                    )
                Text("自动分类")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if queueCount > 0 {
                    Text("还有 \(queueCount) 个")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if let result = pending {
                SuggestionCard(result: result,
                               rememberRule: $rememberRule,
                               onCommit: onCommit,
                               onSkip: onSkip)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .top)
                            .combined(with: .offset(y: -10))
                            .combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.96))))
            } else {
                dropZone
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: pending?.fingerprint.url)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(isTargeted ? Color.accentColor.opacity(0.9) : settings.appBorder)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                )

            VStack(spacing: 8) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: isTargeted)
                Text(isTargeted ? "松手开始识别" : "把文件拖到这里")
                    .font(.system(size: 12.5, weight: .medium))
                Text("自动判断该放进哪个模块")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - 建议卡片

private struct SuggestionCard: View {
    @EnvironmentObject var store: ShelfStore
    @ObservedObject private var settings = ShelfSettings.shared
    let result: ClassificationResult
    @Binding var rememberRule: Bool
    let onCommit: (UUID) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 文件头
            HStack(spacing: 10) {
                FileIconView(url: result.fingerprint.url, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.fingerprint.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(2)
                    Text((result.fingerprint.parentFolder as NSString).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { onSkip() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("跳过这个文件")
            }

            ShelfDivider()

            if result.candidates.isEmpty {
                VStack(spacing: 8) {
                    Text("没找到明显匹配的模块")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    manualPicker
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                // 首选
                if let primary = result.primary {
                    CandidateButton(candidate: primary, prominent: true) {
                        onCommit(primary.moduleID)
                    }
                }

                // 次选
                if !result.alternates.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("次选")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(result.alternates) { c in
                            CandidateButton(candidate: c, prominent: false) {
                                onCommit(c.moduleID)
                            }
                        }
                    }
                }

                HStack {
                    Menu {
                        ForEach(store.modules) { m in
                            Button("\(m.name)") { onCommit(m.id) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("其他模块…")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 96)

                    Spacer()

                    Toggle("记住这条规则", isOn: $rememberRule)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            // AI 状态
            if result.aiState == .loading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                    Text("正在询问 AI…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else if result.aiState == .failed {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                    Text("AI 不可用，以上为本地判断")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.orange)
            } else if result.aiState == .done {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                    Text("AI 已参与判断")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.purple)
            }
        }
        .padding(12)
        .background(Material.thick, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(settings.appBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var manualPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 6) {
            ForEach(store.modules) { m in
                ModuleChipButton(module: m) { onCommit(m.id) }
            }
        }
    }
}

/// 手动归档的模块小按钮（带 hover + 按下反馈）
private struct ModuleChipButton: View {
    let module: ShelfModule
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: module.symbol).font(.system(size: 10))
                Text(module.name).font(.system(size: 11)).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(module.accent.opacity(hovered ? 0.26 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(module.accent.opacity(hovered ? 0.55 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(PressChipStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.1), value: hovered)
        .foregroundStyle(module.accent)
    }
}

// MARK: - 候选按钮

private struct CandidateButton: View {
    let candidate: ClassificationCandidate
    let prominent: Bool
    let action: () -> Void

    @State private var hovered = false

    private var accent: Color { Color(hexString: candidate.accentHex) ?? .accentColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: candidate.symbol)
                    .font(.system(size: prominent ? 13 : 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: prominent ? 28 : 22, height: prominent ? 28 : 22)
                    .background(accent.gradient,
                                in: RoundedRectangle(cornerRadius: prominent ? 8 : 6, style: .continuous))

                VStack(alignment: .leading, spacing: prominent ? 2 : 1) {
                    HStack(spacing: 5) {
                        Text(candidate.moduleName)
                            .font(.system(size: prominent ? 13 : 11.5, weight: .semibold))
                        if candidate.isAI {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8))
                                .foregroundStyle(.purple)
                        }
                        Spacer(minLength: 0)
                        ConfidenceRing(value: candidate.confidence,
                                       color: accent,
                                       size: prominent ? 22 : 18)
                    }
                    if prominent, !candidate.reasons.isEmpty {
                        Text(candidate.reasons.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, prominent ? 9 : 6)
            .background(
                RoundedRectangle(cornerRadius: prominent ? 11 : 8, style: .continuous)
                    .fill(hovered ? accent.opacity(0.22) : accent.opacity(prominent ? 0.13 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: prominent ? 11 : 8, style: .continuous)
                    .strokeBorder(accent.opacity(hovered ? 0.8 : (prominent ? 0.45 : 0.2)), lineWidth: 1)
            )
        }
        .buttonStyle(PressChipStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.1), value: hovered)
    }
}

struct ConfidenceRing: View {
    let value: Int
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(value) / 100.0)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)")
                .font(.system(size: size < 20 ? 7.5 : 8.5, weight: .semibold))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .help("匹配置信度 \(value)%")
    }
}
