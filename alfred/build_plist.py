#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dyna Capture の Alfred ワークフロー info.plist を組み立てる。"""
import plistlib

SF = "6A1B0C7E-0001-4D2A-9C11-DC0000000001"   # Script Filter
RUN = "6A1B0C7E-0002-4D2A-9C11-DC0000000002"  # Run Script
NOTE = "6A1B0C7E-0003-4D2A-9C11-DC0000000003" # Notification

wf = {
    "bundleid": "io.github.inbox-tools.dynacapture",
    "category": "Productivity",
    "createdby": "inbox-tools",
    "description": "Alfred から Dynalist の Inbox へ直送する（Dyna Capture）",
    "disabled": False,
    "name": "Dyna Capture",
    "readme": (
        "capture 思いついたこと            → Dynalist の Inbox に1項目\n"
        "capture 親 // 子1 // 子2          → 親の下に子項目\n"
        "capture 親 // 子 /// 孫           → スラッシュを1本増やすと1段深くなる\n"
        "capture（本文なし）               → 入力窓（PWA）を開く\n"
        "⌘ を押しながら決定                → チェックボックス付き（タスク）で送る\n\n"
        "API トークンは macOS キーチェーン（サービス名 dynalist-api）から読む。"
        "ワークフロー内には保存していない。"
    ),
    "version": "1.0.0",
    "webaddress": "https://github.com/inbox-tools/dyna-capture",
    "variablesdontexport": [],
    "connections": {
        SF: [{
            "destinationuid": RUN,
            "modifiers": 0, "modifiersubtext": "", "vitoclose": False,
        }],
        RUN: [{
            "destinationuid": NOTE,
            "modifiers": 0, "modifiersubtext": "", "vitoclose": False,
        }],
    },
    "objects": [
        {
            "uid": SF,
            "type": "alfred.workflow.input.scriptfilter",
            "version": 3,
            "config": {
                "alfredfiltersresults": False,
                "alfredfiltersresultsmatchmode": 0,
                "argumenttreatemptyqueryasnil": False,
                "argumenttrimmode": 0,
                "argumenttype": 1,          # 引数は任意
                "escaping": 102,   # {query} 方式で渡る場合に " $ \\ ` を逃がす
                "keyword": "capture",
                "queuedelaycustom": 3,
                "queuedelayimmediatelyinitially": True,
                "queuedelaymode": 0,
                "queuemode": 1,
                "runningsubtext": "Dynalist に送っています…",
                "script": './capture.py filter "$1" "{query}"',
                "scriptargtype": 1,         # with input as argv
                "scriptfile": "",
                "subtext": "本文を打つと Inbox に直送。空のまま決定で入力窓を開く",
                "title": "Dyna Capture",
                "type": 0,                  # bash
                "withspace": True,
            },
        },
        {
            "uid": RUN,
            "type": "alfred.workflow.action.script",
            "version": 2,
            "config": {
                "concurrently": False,
                "escaping": 102,
                "script": './capture.py send "$1" "{query}"',
                "scriptargtype": 1,
                "scriptfile": "",
                "type": 0,                  # bash
            },
        },
        {
            "uid": NOTE,
            "type": "alfred.workflow.output.notification",
            "version": 1,
            "config": {
                "lastpathcomponent": False,
                "onlyshowifquerypopulated": True,
                "removeextension": False,
                "text": "{query}",
                "title": "Dyna Capture",
            },
        },
    ],
    "uidata": {
        SF:   {"xpos": 40,  "ypos": 40},
        RUN:  {"xpos": 300, "ypos": 40},
        NOTE: {"xpos": 560, "ypos": 40},
    },
}

with open("info.plist", "wb") as f:
    plistlib.dump(wf, f)
print("info.plist を書き出しました")
