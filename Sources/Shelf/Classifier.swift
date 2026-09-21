import Foundation
import AppKit

// MARK: - 文件指纹

struct FileFingerprint {
    let url: URL
    let name: String
    let stem: String
    let ext: String
    let path: String
    let parentFolder: String
    let tokens: Set<String>

    init(url: URL) {
        self.url = url
        let name = url.lastPathComponent
        self.name = name
        let ns = name as NSString
        self.ext = ns.pathExtension.lowercased()
        self.stem = ns.deletingPathExtension
        let p = url.path
        self.path = p
        self.parentFolder = (p as NSString).deletingLastPathComponent
        self.tokens = FileFingerprint.tokenize(self.stem)
    }

    /// 把文件名切成 token。既保留完整串（abc123），也保留字母前缀（abc）。
    static func tokenize(_ s: String) -> Set<String> {
        let lower = s.lowercased()
        var out: [String] = []
        var cur = ""
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                cur.append(ch)
            } else {
                if !cur.isEmpty { out.append(cur) }
                cur = ""
            }
        }
        if !cur.isEmpty { out.append(cur) }

        var extra: [String] = []
        for t in out {
            // abc123 -> abc ; hw2 -> hw
            if let idx = t.firstIndex(where: { $0.isNumber }) {
                let pre = String(t[t.startIndex..<idx])
                if pre.count >= 2 { extra.append(pre) }
            }
            // 驼峰切分：LTIResponse -> lti, response
            let camel = t.splitCamel()
            if camel.count > 1 { extra.append(contentsOf: camel) }
        }
        return Set(out + extra).filter { !$0.isEmpty }
    }
}

extension String {
    func splitCamel() -> [String] {
        guard count >= 4 else { return [] }
        var parts: [String] = []
        var cur = ""
        let chars = Array(self)
        for (i, ch) in chars.enumerated() {
            if i > 0, ch.isLetter, ch.isUppercase {
                if !cur.isEmpty { parts.append(cur.lowercased()) }
                cur = String(ch)
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { parts.append(cur.lowercased()) }
        return parts.filter { $0.count >= 2 }
    }
}

// MARK: - 候选结果

struct ClassificationCandidate: Identifiable, Hashable {
    var id: UUID { moduleID }
    let moduleID: UUID
    let moduleName: String
    let accentHex: String
    let symbol: String
    let confidence: Int      // 0...98
    let reasons: [String]
    let source: Source

    enum Source: Hashable { case rule, ai }

    var isAI: Bool { source == .ai }
}

struct ClassificationResult {
    let fingerprint: FileFingerprint
    var candidates: [ClassificationCandidate]
    var aiNote: String?
    var aiState: AIState = .idle

    enum AIState { case idle, loading, done, failed }

    var primary: ClassificationCandidate? { candidates.first }
    var alternates: [ClassificationCandidate] { Array(candidates.dropFirst()) }
}

// MARK: - 规则引擎

enum RuleEngine {

    private static func confidence(from score: Double) -> Int {
        // 0 分 -> 0%，30 分 -> 60%，80 分 -> 88%，120 分 -> 93%
        let c = 95.0 * (1.0 - exp(-score / 30.0))
        return Int(round(min(95.0, max(0.0, c))))
    }

    static func classify(_ fp: FileFingerprint,
                         modules: [ShelfModule],
                         rules: [LearnedRule],
                         existingFoldersByModule: [UUID: Set<String>]) -> [ClassificationCandidate] {

        let pathLower = fp.path.lowercased()
        let stemLower = fp.stem.lowercased()

        var results: [ClassificationCandidate] = []

        for module in modules {
            var score = 0.0
            var reasons: [String] = []
            var matched = Set<String>()

            // 1) 模块名本身出现在文件名里（最强信号）
            let modKey = module.name.lowercased()
            if fp.tokens.contains(modKey) || stemLower.contains(modKey) {
                score += 16
                reasons.append("文件名里有「\(module.name)」")
                matched.insert(modKey)
            }

            // 2) 关键词 —— 精确 token 命中
            for t in fp.tokens {
                if let kw = module.keywords.first(where: { $0.lowercased() == t }),
                   matched.insert(kw.lowercased()).inserted {
                    score += 12
                    reasons.append("名称含「\(kw)」")
                }
            }
            // 3) 关键词 —— 前缀/词根关系（abc ↔ abc123）
            for t in fp.tokens {
                if let kw = module.keywords.first(where: {
                    let k = $0.lowercased()
                    return (k.hasPrefix(t) || t.hasPrefix(k)) && !matched.contains(k)
                }), matched.insert(kw.lowercased()).inserted {
                    score += 9
                    reasons.append("名称匹配「\(kw)」")
                }
            }
            // 4) 关键词 —— 子串命中（中文必备；也覆盖路径）
            for kw in module.keywords where kw.count >= 2 {
                let k = kw.lowercased()
                if matched.contains(k) { continue }
                if stemLower.contains(k) {
                    matched.insert(k); score += 10
                    reasons.append("名称含「\(kw)」")
                } else if pathLower.contains(k) {
                    matched.insert(k); score += 6
                    reasons.append("所在路径含「\(kw)」")
                }
            }

            // 5) 你手动纠正过、被记住的规则
            for r in rules where r.moduleID == module.id {
                if fp.tokens.contains(r.token) || stemLower.contains(r.token) {
                    let bonus = 18.0 + min(8.0, Double(r.hits) * 2.0)
                    score += bonus
                    reasons.append("你以前把「\(r.token)」放进过这里")
                }
            }

            // 6) 这个模块里已经有来自同一文件夹的文件
            if let folders = existingFoldersByModule[module.id], folders.contains(fp.parentFolder) {
                score += 7
                reasons.append("这里已有同文件夹的其他文件")
            }

            // 7) 扩展名亲和度（弱信号）
            score += extAffinity(ext: fp.ext, module: module)

            guard score > 0 else { continue }

            let uniq = Array(NSOrderedSet(array: reasons)) as? [String] ?? reasons
            results.append(ClassificationCandidate(moduleID: module.id,
                                                   moduleName: module.name,
                                                   accentHex: module.accentHex,
                                                   symbol: module.symbol,
                                                   confidence: confidence(from: score),
                                                   reasons: Array(uniq.prefix(3)),
                                                   source: .rule))
        }

        results.sort { $0.confidence > $1.confidence }
        // 置信度差距太小的并列候选保留，最多给 1 个首选 + 3 个次选
        return Array(results.prefix(4))
    }

    private static func extAffinity(ext: String, module: ShelfModule) -> Double {
        let codeExts: Set<String> = ["py", "js", "ts", "swift", "c", "cpp", "h", "hpp", "rs",
                                     "go", "sh", "java", "ino", "json", "yaml", "yml", "xcodeproj"]
        let mediaExts: Set<String> = ["jpg", "jpeg", "png", "heic", "mov", "mp4", "gif"]
        let financeExts: Set<String> = ["xlsx", "xls", "csv", "numbers"]

        let name = module.name.lowercased()
        if name.contains("project") { return codeExts.contains(ext) ? 5 : 0 }
        if name.contains("personal") { return mediaExts.contains(ext) ? 4 : 0 }
        if name.contains("finance") { return financeExts.contains(ext) ? 6 : 0 }
        return 0
    }

    /// 「记住这条规则」时，从文件名里挑一个最具代表性的 token
    static func representativeToken(for fp: FileFingerprint) -> String {
        let stop: Set<String> = ["hw", "lecture", "lec", "tutorial", "tut", "week", "chapter",
                                 "ch", "final", "midterm", "copy", "v1", "v2", "v3", "draft",
                                 "new", "old", "the", "and", "for", "notes", "note"]
        let sorted = fp.tokens
            .filter { $0.count >= 3 && !stop.contains($0) && !$0.allSatisfy { $0.isNumber } }
            .sorted { $0.count > $1.count }
        if let best = sorted.first { return best }
        return fp.stem.lowercased()
    }
}

// MARK: - AI 增强

enum AIClassifier {

    struct AISuggestion {
        var primaryName: String
        var alternateNames: [String]
        var reason: String
    }

    static func suggest(fp: FileFingerprint,
                        modules: [ShelfModule],
                        apiKey: String,
                        model: String,
                        baseURL: String) async throws -> AISuggestion {

        guard let url = URL(string: baseURL), !apiKey.isEmpty else {
            throw URLError(.badURL)
        }

        let moduleList = modules.map { "\($0.name)（关键词：\($0.keywords.prefix(12).joined(separator: "、"))）" }
            .joined(separator: "\n")

        let parent = (fp.parentFolder as NSString).lastPathComponent
        let prompt = """
        你是一个文件归类助手。用户有多个收纳模块，请根据文件名和路径判断这个文件最适合放进哪个模块。

        可选模块：
        \(moduleList)

        待归类文件：
        - 文件名：\(fp.name)
        - 所在文件夹：\(parent)
        - 完整路径：\(fp.path)

        只输出 JSON，不要解释，不要代码块，格式：
        {"primary":"模块名","alternates":["模块名","模块名"],"reason":"一句话中文理由，20字以内"}
        规则：primary 必须是上面列出的模块名之一；alternates 最多 2 个，且不能与 primary 重复；不要输出不存在的模块名。
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你只输出合法 JSON，不输出任何其他内容。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0,
            "stream": false
        ]

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let cdata = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: cdata) as? [String: Any],
              let primary = obj["primary"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        let alternates = (obj["alternates"] as? [String]) ?? []
        let reason = (obj["reason"] as? String) ?? ""

        return AISuggestion(primaryName: primary, alternateNames: alternates, reason: reason)
    }
}
