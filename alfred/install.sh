#!/usr/bin/env bash
# alfred/ のソースを Alfred のワークフローフォルダへ反映して Alfred を再起動する
set -euo pipefail
cd "$(dirname "$0")"
WF="$HOME/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows/user.workflow.dynacapture"
python3 build_plist.py
mkdir -p "$WF"
cp capture.py info.plist icon.png "$WF/"
chmod +x "$WF/capture.py"
osascript -e 'tell application "Alfred 4" to quit' 2>/dev/null || true
sleep 2
open -a "Alfred 4"
echo "導入しました: $WF"
