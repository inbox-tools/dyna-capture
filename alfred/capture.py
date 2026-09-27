#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dyna Capture — Alfred から Dynalist の Inbox へ直送する。

使い方（Alfred で `capture` と打つ）:
  capture 思いついたこと              → Inbox に1項目
  capture 親 // 子1 // 子2            → 親の下に子項目
  capture 親 // 子 /// 孫             → スラッシュを増やすと1段深くなる
  capture                             → 入力窓（PWA）を開く
  ⌘ を押しながら決定                  → チェックボックス付き（タスク）で送る

トークンは macOS キーチェーン（サービス名 dynalist-api）から読む。
ワークフロー側には保存しない。
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://dynalist.io/api/v1/"
MAC_APP = os.path.expanduser("~/Applications/Dyna Capture.app")
APP_URL = "https://inbox-tools.github.io/dyna-capture/"
KEYCHAIN_SERVICE = "dynalist-api"

ERRORS = {
    "InvalidToken": "トークンが違います。キーチェーンの dynalist-api を確認してください",
    "NoInbox": "Dynalist 側で Inbox が未設定です（項目を右クリック → Set as inbox）",
    "LockFail": "Dynalist 側がロック中です。少し待ってもう一度",
    "TooManyRequests": "送信が多すぎます。少し待ってください",
    "Invalid": "リクエストが不正です",
}


class ApiError(Exception):
    def __init__(self, code, msg=""):
        self.code = code
        super().__init__(ERRORS.get(code) or msg or code or "送信に失敗しました")


LOG = os.path.expanduser("~/Library/Logs/dyna-capture.log")


def log(*parts):
    """Alfred から本当に呼ばれているかを後から確かめるための記録。"""
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s\t%s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"),
                                   "\t".join(str(p).replace("\n", "\\n") for p in parts)))
    except Exception:
        pass


def get_token():
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10,
        )
    except Exception:
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def api(path, token, body):
    payload = dict(body)
    payload["token"] = token
    req = urllib.request.Request(
        API + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": "curl/8.4.0"},
        method="POST",
    )
    # Dynalist は素の Python UA を 403 で弾くので UA を必ず付ける
    with urllib.request.urlopen(req, timeout=20) as res:
        j = json.loads(res.read().decode("utf-8"))
    if j.get("_code") != "Ok":
        raise ApiError(j.get("_code"), j.get("_msg", ""))
    return j


def parse_tree(text):
    """`//` 区切りを親子ツリーに分解する。スラッシュが1本増えるごとに1段深くなる。"""
    parts = [p for p in re.split(r"\s*(/{2,})\s*", text.strip()) if p]
    if not parts:
        return None
    root = parts[0].strip()
    nodes = []
    i = 1
    while i < len(parts) - 1:
        sep, content = parts[i], parts[i + 1].strip()
        if content:
            nodes.append({"content": content, "depth": len(sep) - 1})
        i += 2
    # 段飛ばし（親 /// 孫）を詰めて、親のいない深さを作らない
    fixed, prev = [], 0
    for n in nodes:
        d = min(n["depth"], prev + 1)
        fixed.append({"content": n["content"], "depth": d})
        prev = d
    return {"root": root, "nodes": fixed}


def insert_children(token, file_id, root_id, nodes, checkbox):
    """階層ごとに1リクエスト。index は 0,1,2… と明示（-1 は先頭挿入になり逆順化する）。"""
    ids = [None] * len(nodes)

    def parent_of(i):
        for j in range(i - 1, -1, -1):
            if nodes[j]["depth"] == nodes[i]["depth"] - 1:
                return ids[j] or root_id
        return root_id

    next_index = {root_id: 0}
    max_depth = max(n["depth"] for n in nodes)
    for d in range(1, max_depth + 1):
        idx = [i for i, n in enumerate(nodes) if n["depth"] == d]
        if not idx:
            continue
        changes = []
        for i in idx:
            pid = root_id if d == 1 else parent_of(i)
            at = next_index.get(pid, 0)
            next_index[pid] = at + 1
            changes.append({
                "action": "insert", "parent_id": pid, "index": at,
                "content": nodes[i]["content"], "checkbox": checkbox,
            })
        r = api("doc/edit", token, {"file_id": file_id, "changes": changes})
        for k, new_id in enumerate(r.get("new_node_ids", [])):
            ids[idx[k]] = new_id


def send(text, checkbox):
    token = get_token()
    if not token:
        return "キーチェーンに dynalist-api のトークンがありません"
    tree = parse_tree(text)
    if not tree or not tree["root"]:
        return "送る内容がありません"
    r = api("inbox/add", token, {"content": tree["root"], "note": "", "checkbox": checkbox})
    n_child = 0
    if tree["nodes"]:
        try:
            insert_children(token, r["file_id"], r["node_id"], tree["nodes"], checkbox)
            n_child = len(tree["nodes"])
        except ApiError as e:
            return "親は送れましたが子項目で失敗: %s" % e
    label = "タスク" if checkbox else "メモ"
    suffix = "（子 %d 件）" % n_child if n_child else ""
    return "%s を送りました%s ✓ %s" % (label, suffix, tree["root"][:40])


def cmd_filter(query):
    q = (query or "").strip()
    items = []
    if not get_token():
        items.append({
            "title": "トークンが見つかりません",
            "subtitle": "キーチェーンに dynalist-api を登録してください",
            "valid": False,
        })
    elif not q:
        # 本文なしで決定したら入力窓を開く（これが既定）
        items.append({
            "title": "入力窓を開く",
            "subtitle": "複数行で書ける。改行が子項目、行頭にスペースを足すともう1段深く",
            "arg": json.dumps({"action": "open"}, ensure_ascii=False),
        })
        items.append({
            "title": "1行だけなら、capture のうしろに続けて打つと直送します",
            "subtitle": "例）capture 明日の面談で価格の話をする",
            "valid": False,
        })
    else:
        tree = parse_tree(q)
        kids = tree["nodes"] if tree else []
        sub = "子: " + " / ".join(n["content"] for n in kids) if kids else "⌘ でタスク（チェックボックス）として送る"
        items.append({
            "title": tree["root"],
            "subtitle": "Dynalist の Inbox に送る　%s" % sub,
            "arg": json.dumps({"action": "send", "text": q, "checkbox": False}, ensure_ascii=False),
            "mods": {
                "cmd": {
                    "valid": True,
                    "subtitle": "チェックボックス付き（タスク）として送る",
                    "arg": json.dumps({"action": "send", "text": q, "checkbox": True}, ensure_ascii=False),
                }
            },
        })
    sys.stdout.write(json.dumps({"items": items}, ensure_ascii=False))


def cmd_send(raw):
    try:
        payload = json.loads(raw)
    except Exception:
        payload = {"action": "send", "text": raw, "checkbox": False}
    if payload.get("action") == "open":
        # Mac アプリがあればそれを開く。無ければブラウザ版に落とす
        if os.path.isdir(MAC_APP):
            subprocess.run(["open", "-a", MAC_APP])
        else:
            subprocess.run(["open", APP_URL])
        sys.stdout.write("Dyna Capture を開きました")
        return
    try:
        msg = send(payload.get("text", ""), bool(payload.get("checkbox")))
    except ApiError as e:
        msg = str(e)
    except urllib.error.URLError:
        msg = "ネットにつながりません。オフライン時は入力窓（capture のみで決定）を使ってください"
    except Exception as e:
        msg = "送信に失敗しました: %s" % e
    sys.stdout.write(msg)


def read_input(allow_stdin):
    """Alfred の引数受け渡しは argv / {query} / stdin の3通りありうる。
    どれで渡ってきても拾えるようにする。

    ただし stdin を無条件に読むと、何も流れてこないときに待ち続けて固まる。
    Script Filter は必ず引数で渡ってくるので stdin は読まない。送信側だけ、
    読めるデータが実際にあるときに限って読む。"""
    args = [a for a in sys.argv[2:] if a.strip() and a.strip() != "{query}"]
    if args:
        return args[0]
    if allow_stdin and not sys.stdin.isatty():
        import select
        r, _, _ = select.select([sys.stdin], [], [], 2.0)
        if r:
            try:
                return sys.stdin.read()
            except Exception:
                pass
    return ""


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "filter"
    payload = read_input(allow_stdin=(mode != "filter"))
    log("MODE=%s" % mode, "ARGV=%r" % (sys.argv[1:],), "INPUT=%r" % payload, "CWD=%s" % os.getcwd())
    try:
        if mode == "filter":
            cmd_filter(payload)
        else:
            cmd_send(payload)
    except Exception as e:
        log("ERROR", repr(e))
        raise
