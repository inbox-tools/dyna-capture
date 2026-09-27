# Dyna Capture — Dynalist 即メモ（DynaWrite 代替）

思いついた瞬間に Dynalist の Inbox へ 1 タップで放り込むための、iPhone ホーム画面アプリ（PWA）。
サーバー不要・ランニングコスト 0 円。静的 HTML から Dynalist 公式 API を直接叩くだけ。

## できること
- 書く → 「Dynalist の Inbox に送る」だけ。送信後は即クリアされ、次のメモが書ける
- ノート欄（任意）／チェックボックス（タスク化）
- **改行するとツリーになる**。1行目が親、2行目以降がその子項目。行頭のスペース1つ（半角・全角どちらでも）または Tab 1つで、さらに深い階層に入る（設定でオフにすれば改行込みの1項目として送る）
- 日付・時刻のワンタップ挿入
- 定型文ボタン（設定で自由に編集。1行1つ）
- オフラインでも書ける。圏外時は端末に貯めて、次にオンラインになったとき自動送信
- 送信履歴 30 件を設定画面で確認
- ⌘/Ctrl + Enter で送信（PC ブラウザ用）

## 仕組み
- `POST https://dynalist.io/api/v1/inbox/add`（CORS 許可済みなのでブラウザから直接叩ける）
- 子項目はレスポンスの `file_id` / `node_id` を親にして `doc/edit` の insert で追加。1階層につき 1 リクエスト
- 子の挿入中に通信が切れた場合、未挿入分はキューに退避して次回送信する（再送分は親の直下に平らに並ぶ）
- 保存先は Dynalist 側の「Inbox」設定に従う（項目を右クリック →「Set as inbox」）
- API トークンは端末の localStorage にのみ保存。第三者サーバーは一切経由しない

## セットアップ
1. https://dynalist.io/developer で API トークンを発行
2. Dynalist で Inbox にしたい項目／ドキュメントを右クリック →「Set as inbox」
3. 公開 URL を iPhone の Safari で開く → 共有 → 「ホーム画面に追加」
4. 初回に開く設定シートへトークンを貼って保存

## Mac から使う

### 1. アプリ本体（複数行を書くとき／ふだんはこちら）

Alfred で `capture` → Enter で入力窓が出る。書いて `⌘↩` で Dynalist の Inbox へ。
メニューバーのトレイアイコンからも開ける。Dock には出ない常駐アプリ。

グローバルホットキーは**あえて持たせていない**（`⌘⇧Space` などは他アプリと取り合いになるため）。
呼び出し口は Alfred とメニューバーの2つ。

```
打ち合わせメモ          ← 1行目が親
 価格の話               ← 行頭にスペース1つで子
  55万の根拠            ← スペース2つで孫
 納期の話
```

iPhone 版とまったく同じ規則（改行で子項目・行頭スペースまたはTabで1段深く）。
API トークンは macOS キーチェーン（サービス名 `dynalist-api`）から読むので、
ブラウザ版のようにトークンを貼る必要はない。

- ソース: `mac/Sources/`（`Dynalist.swift` = API と階層解析、`main.swift` = UI）
- ビルド: `mac/build.sh` → `mac/build/Dyna Capture.app`
- 設置先: `~/Applications/Dyna Capture.app`
- メニューバーの「ログイン時に起動」で自動起動を切り替えられる
- 窓はマウスのある画面に出る（2画面でも見ている側に出る）
- `↩` は改行、`⌘↩` が送信。`esc` で閉じる

### 2. Alfred ワークフロー（1行メモを最速で放り込むとき）

Alfred を出して `capture 本文` と打てば、そのまま Dynalist の Inbox に入る。

```
capture 明日の面談で価格の話をする        → Inbox に1項目
capture 打ち合わせ // 価格の話 // 納期     → 親の下に子項目
capture 打ち合わせ // 価格 /// 55万の根拠  → スラッシュを1本増やすと1段深くなる
capture（本文なし）                       → 上の Mac アプリの入力窓を開く
⌘ を押しながら決定                        → チェックボックス付き（タスク）で送る
```

iPhone 版の「改行で子項目」を、1行で打てるよう `//` に置き換えただけで、
送信の中身（`inbox/add` → 子は `doc/edit` の insert・index は明示）は同じ。

- ソースは `alfred/`（`capture.py` と、info.plist を組み立てる `build_plist.py`）
- 導入先は `~/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows/user.workflow.dynacapture`
- 更新したら `alfred/install.sh` を実行して Alfred を再起動する
- **API トークンは macOS キーチェーン（サービス名 `dynalist-api`）から読む**。ワークフロー内には持たない

## ファイル
- `index.html` — アプリ本体（単一ファイル）
- `mac/` — Mac アプリ（Swift）のソース
- `alfred/` — Alfred ワークフローのソース
- `sw.js` — Service Worker（オフライン起動用）
- `manifest.webmanifest` / `icon-*.png` — ホーム画面アイコン・スタンドアロン表示

## ローカル確認
```
cd claude-code/apps/dynalist-capture && python3 -m http.server 8777
# → http://127.0.0.1:8777/
```
