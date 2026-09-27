import Foundation

// MARK: - Dynalist API

struct DynalistError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
    /// 再送しても無駄なエラーか
    var isFatal: Bool { ["InvalidToken", "NoInbox", "Invalid"].contains(code) }

    static func from(code: String?, msg: String?) -> DynalistError {
        let table = [
            "InvalidToken": "トークンが違います。キーチェーンの dynalist-api を確認してください",
            "NoInbox": "Dynalist 側で Inbox が未設定です（項目を右クリック → Set as inbox）",
            "LockFail": "Dynalist 側がロック中です。少し待ってもう一度",
            "TooManyRequests": "送信が多すぎます。少し待ってください",
            "Invalid": "リクエストが不正です",
        ]
        let c = code ?? ""
        let fallback = (msg?.isEmpty == false ? msg! : c)
        let text = table[c] ?? (fallback.isEmpty ? "送信に失敗しました" : fallback)
        return DynalistError(code: c, message: text)
    }
}

struct TreeNode {
    let content: String
    let depth: Int
}

struct Tree {
    let root: String
    let nodes: [TreeNode]
}

enum Dynalist {
    static let base = URL(string: "https://dynalist.io/api/v1/")!
    static let keychainService = "dynalist-api"

    /// トークンは macOS キーチェーンから読む。アプリ側には保存しない。
    /// SecItem ではなく security コマンド経由にしているのは、キーチェーン項目の
    /// ACL が /usr/bin/security を信頼しているため（未署名アプリだと SecItem は弾かれる）。
    static func token() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }

    /// 同期呼び出し。UI を止めないよう、必ずバックグラウンドから呼ぶこと。
    static func call(_ path: String, token: String, body: [String: Any]) throws -> [String: Any] {
        var payload = body
        payload["token"] = token

        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 25

        var result: [String: Any]?
        var failure: Error?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, err in
            defer { sem.signal() }
            if let err = err { failure = err; return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                failure = DynalistError(code: "", message: "Dynalist の応答を読めませんでした")
                return
            }
            result = json
        }.resume()
        sem.wait()

        if let failure = failure {
            if (failure as NSError).domain == NSURLErrorDomain {
                throw DynalistError(code: "Offline", message: "ネットにつながりません")
            }
            throw failure
        }
        guard let json = result else {
            throw DynalistError(code: "", message: "送信に失敗しました")
        }
        let code = json["_code"] as? String
        guard code == "Ok" else {
            throw DynalistError.from(code: code, msg: json["_msg"] as? String)
        }
        return json
    }

    /// 入力を「1行目＝親／2行目以降＝子」のツリーに分解する。
    /// 行頭のスペース1つ（半角・全角どちらでも）または Tab 1つで1段深くなる。
    /// iPhone 版（index.html の parseTree）と同じ規則。
    static func parseTree(_ text: String) -> Tree? {
        let raw = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !raw.isEmpty else { return nil }

        var parsed: [(lvl: Int, content: String)] = raw.map { line in
            let indent = line.prefix { $0 == "\t" || $0 == " " || $0 == "\u{3000}" }
            var body = line.trimmingCharacters(in: .whitespaces)
            for bullet in ["- ", "* ", "・"] where body.hasPrefix(bullet) {
                body = String(body.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            return (indent.count, body)
        }

        let root = parsed.removeFirst().content
        var nodes: [TreeNode] = []
        var stack: [Int] = []          // 祖先の字下げ幅。深さ = stack.count
        for item in parsed {
            while let last = stack.last, item.lvl < last { stack.removeLast() }
            if stack.isEmpty || item.lvl > stack.last! { stack.append(item.lvl) }
            nodes.append(TreeNode(content: item.content, depth: stack.count))
        }
        return Tree(root: root, nodes: nodes)
    }

    /// 子項目を階層ごとにまとめて挿入する。1階層 = doc/edit 1回。
    /// index:-1 は「末尾追加」ではなく先頭挿入として効き、一括分が逆順になるので
    /// 必ず 0,1,2… と親ごとに明示指定する。
    static func insertChildren(fileId: String, rootId: String, nodes: [TreeNode],
                               checkbox: Bool, token: String) throws {
        var ids = [String?](repeating: nil, count: nodes.count)

        func parent(of i: Int) -> String {
            var j = i - 1
            while j >= 0 {
                if nodes[j].depth == nodes[i].depth - 1 { return ids[j] ?? rootId }
                j -= 1
            }
            return rootId
        }

        var nextIndex: [String: Int] = [rootId: 0]
        let maxDepth = nodes.map(\.depth).max() ?? 0

        for d in 1...max(maxDepth, 1) {
            let idx = nodes.indices.filter { nodes[$0].depth == d }
            if idx.isEmpty { continue }
            var changes: [[String: Any]] = []
            for i in idx {
                let pid = d == 1 ? rootId : parent(of: i)
                let at = nextIndex[pid] ?? 0
                nextIndex[pid] = at + 1
                changes.append([
                    "action": "insert", "parent_id": pid, "index": at,
                    "content": nodes[i].content, "checkbox": checkbox,
                ])
            }
            let r = try call("doc/edit", token: token, body: ["file_id": fileId, "changes": changes])
            if let newIds = r["new_node_ids"] as? [String] {
                for (k, id) in newIds.enumerated() where k < idx.count { ids[idx[k]] = id }
            }
        }
    }

    struct SendResult {
        let root: String
        let childCount: Int
        let checkbox: Bool
    }

    static func send(text: String, note: String, checkbox: Bool) throws -> SendResult {
        guard let token = token() else {
            throw DynalistError(code: "InvalidToken",
                                message: "キーチェーンに dynalist-api のトークンがありません")
        }
        guard let tree = parseTree(text), !tree.root.isEmpty else {
            throw DynalistError(code: "Invalid", message: "送る内容がありません")
        }
        let r = try call("inbox/add", token: token,
                         body: ["content": tree.root, "note": note, "checkbox": checkbox])
        guard let fileId = r["file_id"] as? String, let nodeId = r["node_id"] as? String else {
            return SendResult(root: tree.root, childCount: 0, checkbox: checkbox)
        }
        if !tree.nodes.isEmpty {
            try insertChildren(fileId: fileId, rootId: nodeId, nodes: tree.nodes,
                               checkbox: checkbox, token: token)
        }
        return SendResult(root: tree.root, childCount: tree.nodes.count, checkbox: checkbox)
    }
}
