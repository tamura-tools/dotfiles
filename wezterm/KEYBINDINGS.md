# WezTerm キーバインド & 機能ガイド

設定ファイル: `~/dotfiles/wezterm/wezterm.lua`

---

## 起動時レイアウト

WezTerm 起動時に5ペインが自動展開される。

```
┌──────┬────────────────────────┬──────────┐
│ yazi │     Claude Code        │          │
│      │   (プロジェクト実行)    │ Claude   │
├──────┼────────────────────────┤ (壁打ち) │
│lazy  │   Sangha Dashboard     │          │
│ git  │                        │          │
└──────┴────────────────────────┴──────────┘
  10%          60%                  30%
```

| ペイン | 内容 | 作業ディレクトリ |
|--------|------|------------------|
| 左上 | yazi（ファイラー） | - |
| 左下 | lazygit | `~/dotfiles` |
| 中央上 | Claude Code（実行者） | `C:\claude` |
| 中央下 | Sangha Dashboard | - |
| 右 | Claude Code（壁打ち） | `~/claude-chat` |

---

## ペイン操作

| キー | 機能 |
|------|------|
| `Ctrl+Shift+D` | ペインを横に分割 |
| `Ctrl+Shift+E` | ペインを縦に分割 |
| `Ctrl+Shift+W` | 現在のペインを閉じる（確認あり） |
| `Ctrl+H` | 左のペインへ移動 |
| `Ctrl+L` | 右のペインへ移動 |
| `Ctrl+K` | 上のペインへ移動 |
| `Ctrl+J` | 下のペインへ移動 |

---

## ランチャーメニュー

**`F9`** でアプリ選択メニューが開く。

現在のペインで動いているプロセスを停止し、選んだアプリに切り替える。

| 選択肢 | 起動コマンド |
|--------|-------------|
| Claude Code | `claudecode` |
| Gemini CLI | `cd C:\claude; gemini` |
| lazygit | `cd ~/dotfiles; lazygit` |
| Sangha Dashboard | `sangha-dashboard.ps1` |
| yazi | `yazi` |
| PowerShell | (シェルに戻る) |

---

## クイック起動

| キー | 機能 |
|------|------|
| `Ctrl+Shift+G` | 現在のペインで lazygit を起動 |
| `Ctrl+Shift+S` | 現在のペインで Sangha Dashboard を起動 |

---

## 外観の一時変更

すべてセッション限りの変更。`wezterm.lua` は書き換わらず、WezTerm を再起動すれば元に戻る。
各メニュー内の「Reset to default」で即座にデフォルトに復帰できる。

### カラースキーム (`Ctrl+Shift+F1`)

14種のダークテーマから選択できる。

| テーマ名 | 備考 |
|----------|------|
| Tokyo Night | デフォルト |
| Tokyo Night Storm | |
| Catppuccin Mocha | |
| Catppuccin Macchiato | |
| Dracula (Gogh) | |
| Gruvbox Dark (Gogh) | |
| Nord | |
| One Half Dark (Gogh) | |
| Solarized Dark (Gogh) | |
| Kanagawa (Gogh) | |
| rose-pine | |
| Everforest Dark (Gogh) | |
| Ayu Dark (Gogh) | |
| nightfox | |

### 壁紙画像 (`Ctrl+Shift+F3`)

`~/dotfiles/wezterm/wallpapers/` フォルダ内の画像ファイルが自動でリストアップされる。
対応形式: jpg, jpeg, png, gif, webp

壁紙を追加するには、そのフォルダに画像ファイルを置くだけでよい。
メニューを開くたびにフォルダをスキャンするので、再起動は不要。

壁紙を変更しても、先に設定した明るさは維持される。

### 壁紙の明るさ (`Ctrl+Shift+F2`)

| 選択肢 | 値 |
|--------|-----|
| Very Dark | 0.03 |
| Dark | 0.07 |
| Default | 0.1 |
| Medium Dark | 0.15 |
| Medium | 0.2 |
| Bright | 0.3 |
| No wallpaper | 壁紙を非表示にする |

明るさを変更しても、先に選んだ壁紙画像は維持される。

---

## 基本設定

| 項目 | 値 |
|------|-----|
| カラースキーム | Tokyo Night |
| フォント | UDEV Gothic NF |
| フォントサイズ | 12 |
| デフォルトシェル | PowerShell (Windows) |
| 作業ディレクトリ | `C:\claude` (Windows) / `~/claude` (Mac/Linux) |
| 壁紙の明るさ | 0.1 |
| 設定の自動リロード | 有効 |
