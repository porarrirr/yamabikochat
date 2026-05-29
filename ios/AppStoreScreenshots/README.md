# App Store Screenshots

## iPhone（6.5インチディスプレイ）

アップロード先: **1284 × 2778 px**（縦）  
代替として **1242 × 2688 px** も可（本フォルダは 1284×2778 で出力）

| ファイル | 内容 |
|---------|------|
| `01-settings-api.png` | 使うAIを自由に選べる（API設定） |
| `02-chat-math.png` | 数式もわかりやすく解説（極限の公式チャット） |
| `03-token-statistics.png` | 利用状況をひと目で把握（トークン統計） |

## iPad（13インチディスプレイ）

アップロード先: **2048 × 2732 px**（縦）  
代替として **2064 × 2752 px** も可（本フォルダは 2048×2732 で出力）

| ファイル | 内容 |
|---------|------|
| `01-split-empty.png` | 分割ビュー（会話リスト＋空の詳細） |
| `02-settings-api.png` | API設定 |
| `03-settings-system-prompt.png` | システムプロンプト設定 |

## 再生成

元画像を差し替えたあと:

```bash
cd ios
python3 scripts/resize-app-store-screenshots.py
```
