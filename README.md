# Dyna Capture — Dynalist 即メモ（DynaWrite 代替）

思いついた瞬間に Dynalist の Inbox へ 1 タップで放り込むための、iPhone ホーム画面アプリ（PWA）。
サーバー不要・ランニングコスト 0 円。静的 HTML から Dynalist 公式 API を直接叩くだけ。

## できること
- 書く → 「Dynalist の Inbox に送る」だけ。送信後は即クリアされ、次のメモが書ける
- ノート欄（任意）／チェックボックス（タスク化）
- **改行するとツリーになる**。1行目が親、2行目以降がその子項目。行頭の Tab・全角スペース1つ・半角スペース2つで、さらに深い階層に入る（設定でオフにすれば改行込みの1項目として送る）
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

## ファイル
- `index.html` — アプリ本体（単一ファイル）
- `sw.js` — Service Worker（オフライン起動用）
- `manifest.webmanifest` / `icon-*.png` — ホーム画面アイコン・スタンドアロン表示

## ローカル確認
```
cd claude-code/apps/dynalist-capture && python3 -m http.server 8777
# → http://127.0.0.1:8777/
```
