# WezTerm キーバインド & 機能ガイド

設定ファイル: `~/dotfiles/wezterm/wezterm.lua`

---

## 起動時レイアウト

WezTerm 起動時に6ペインが自動展開される。

```
┌──────┬────────────────────────┬──────────┐
│ yazi │     Claude Code        │ Codex    │
│      │                        │  CLI     │
├──────┼────────────────────────┼──────────┤
│lazy  │   Obsidian Tasks       │ Gemini   │
│ git  │   (task.py watch)      │  CLI     │
└──────┴────────────────────────┴──────────┘
  比率 1 : 5 : 2（左上下/中央上下/右上下）
```

| ペイン | 内容 |
|--------|------|
| 左上 | yazi（ファイラー） |
| 左下 | lazygit (`~/dotfiles`) |
| 中央上 | Claude Code |
| 中央下 | Obsidian Tasks ダッシュボード (`task.py watch`) |
| 右上 | Codex CLI |
| 右下 | Gemini CLI |

---

## ペイン操作

| キー | 機能 |
|------|------|
| `Ctrl+Shift+D` | ペインを横に分割 |
| `Ctrl+Shift+E` | ペインを縦に分割 |
| `Ctrl+Shift+W` | 現在のペインを閉じる（確認あり） |
| `Ctrl+H` / `Ctrl+L` | 左／右のペインへ移動 |
| `Ctrl+K` / `Ctrl+J` | 上／下のペインへ移動 |

---

## ランチャーメニュー

**`F9`** でアプリ選択メニューが開く。現在のペインで動いているプロセスを停止し、選んだアプリに切り替える。

| 選択肢 | 起動コマンド |
|--------|-------------|
| Claude Code | `claude`（個人アカウント） |
| Claude Code (会社) | `CLAUDE_CONFIG_DIR=~/.claude-work claude` |
| Gemini CLI | `cd ~/claude && gemini` |
| lazygit | `cd ~/dotfiles && lazygit` |
| Obsidian Tasks | `python3 ~/claude/tools/task.py watch`（Win は `python`） |
| Codex CLI | `cd ~/claude && codex` |
| yazi | `yazi` |
| Shell | 何もしない（シェルに戻る） |

---

## クイック起動

| キー | 機能 |
|------|------|
| `Ctrl+Shift+G` | lazygit を起動 |
| `Ctrl+Shift+S` | Obsidian Tasks ダッシュボードを起動 |
| `Alt+Enter` | Claude Code の改行用（ターミナルに渡す） |

---

## 外観の一時変更

すべてセッション限り。`wezterm.lua` は書き換わらず、再起動で元に戻る。各メニューの「Reset to default」で即座にデフォルトに復帰できる。

| メニュー | Windows | macOS |
|----------|---------|-------|
| カラースキーム切替 | `Ctrl+Shift+F1` | `Cmd+Shift+T` |
| 壁紙の明るさ | `Ctrl+Shift+F2` | `Cmd+Shift+B` |
| 壁紙画像の切替 | `Ctrl+Shift+F3` | `Cmd+Shift+I` |
| プロファイル切替（テーマ+壁紙セット） | `Ctrl+Shift+F4` | `Cmd+Shift+P` |

macOS が F1〜F4 を OS 側で奪うため、Mac は Cmd 系に分岐させている。

### カラースキーム

Dark / SF・Cyberpunk / Light あわせて 27 種類を切替可能（Tokyo Night, Catppuccin, Dracula, Gruvbox, Nord, SF Terminal, Neuromancer, Claude Light など）。選択した現在値は `(current)` 表示。

### プロファイル

テーマ・壁紙・明るさ・不透明度をセットで切替。

| ID | 内容 |
|----|------|
| personal | Tokyo Night + デフォルト壁紙 |
| work | Claude Light、壁紙なし |
| work-dark | Catppuccin Mocha + 海の壁紙 |
| sf-terminal | SF Terminal、半透過でデスクトップが透ける |
| neuromancer | Neuromancer + サイバーパンク壁紙 |

### 壁紙画像

`~/dotfiles/wezterm/wallpapers/` 配下の `jpg/jpeg/png/gif/webp` が自動でリストアップされる。ファイルを置くだけで反映（再起動不要）。

### 壁紙の明るさ

| 選択肢 | 値 |
|--------|-----|
| Very Dark | 0.03 |
| Dark | 0.07 |
| Default | 0.1 |
| Medium Dark | 0.15 |
| Medium | 0.2 |
| Bright | 0.3 |
| No wallpaper | 壁紙を非表示にする |

---

## 基本設定

| 項目 | 値 |
|------|-----|
| デフォルトカラースキーム | Tokyo Night |
| フォント | UDEV Gothic NF / 12pt |
| デフォルトシェル | PowerShell (Windows) |
| 作業ディレクトリ | `C:/claude` (Windows) / `~/claude` (Mac/Linux) |
| 壁紙の明るさ | 0.1 |
| 設定の自動リロード | 有効 |
