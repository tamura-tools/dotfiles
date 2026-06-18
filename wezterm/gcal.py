#!/usr/bin/env python
# gcal.py — Google Calendar の当日+数日分のアジェンダを「カード枠つき」で表示する。
# 左中ペイン(calendar.ps1)から定期呼び出しされる前提。tokyo-night 配色(truecolor)で
# Todoist ダッシュボードと統一感を持たせる。幅は OUTER(=既定36)桁を想定。
#
# 資格情報・トークンは dotfiles(git管理下) ではなく ~/.config/gcal/ に置く:
#   ~/.config/gcal/client_secret.json … OAuthデスクトップ クライアント
#   ~/.config/gcal/token.json          … 初回認証で自動生成
#
# 初回だけブラウザ同意が要る:  python gcal.py --auth
# 以降は calendar.ps1 が引数なしで定期実行する。

import os
import sys
import datetime
import unicodedata
from collections import OrderedDict

try:
    sys.stdout.reconfigure(encoding='utf-8')  # パイプ経由でも日本語を化けさせない
except Exception:
    pass

CFG    = os.path.join(os.path.expanduser('~'), '.config', 'gcal')
CLIENT = os.path.join(CFG, 'client_secret.json')
TOKEN  = os.path.join(CFG, 'token.json')
SCOPES = ['https://www.googleapis.com/auth/calendar.readonly']
DAYS   = 3      # 今日から何日先まで
MAXN   = 25

# ── 表示レイアウト ──────────────────────────────────
INNER = 32              # カード内側コンテンツ幅(表示セル)
OUTER = INNER + 4       # 枠込みの外寸
WDAY  = ['月', '火', '水', '木', '金', '土', '日']  # Mon=0

# ── tokyo-night 配色 (Todoist ダッシュボードと統一) ──
ESC = '\x1b'
def _fg(r, g, b):
    return f'{ESC}[38;2;{r};{g};{b}m'
RESET    = f'{ESC}[0m'
BOLD     = f'{ESC}[1m'
C_FG     = _fg(169, 177, 214)
C_ACCENT = _fg(187, 154, 247)   # 紫: 今日・タイトル
C_HI     = _fg(224, 175, 104)   # 琥珀: 終日マーカー・時刻ヘッダ
C_OK     = _fg(158, 206, 106)   # 緑
C_ERR    = _fg(247, 118, 142)   # 赤
C_DIM    = _fg(86, 95, 137)     # 減光
C_CYAN   = _fg(125, 207, 255)   # 時刻
C_BORDER = _fg(60, 64, 90)      # 枠線


def dwidth(s):
    """端末表示セル数(全角=2)。ANSI を含まない素テキストに対して使う。"""
    w = 0
    for ch in s:
        w += 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
    return w


def clip_w(s, maxw):
    """表示幅 maxw に収める(超過は … で打ち切り)。"""
    s = s.replace('\n', ' ').strip()
    if dwidth(s) <= maxw:
        return s
    out, w = '', 0
    for ch in s:
        cw = 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
        if w + cw > maxw - 1:
            break
        out += ch
        w += cw
    return out + '…'


# ── 枠描画ヘルパー ──────────────────────────────────

def row(segments):
    """カード本文1行。segments=[(text, color), ...]。色は表示幅に影響しない。"""
    plain = ''.join(t for t, _ in segments)
    pad = max(0, INNER - dwidth(plain))
    body = ''.join((c + t + RESET) if c else t for t, c in segments)
    return f'{C_BORDER}│{RESET} {body}{" " * pad} {C_BORDER}│{RESET}'


def top_border(clock):
    # ┌─ CALENDAR ───…─── HH:MM ─┐
    fill = OUTER - (3 + len('CALENDAR') + 1 + 1 + len(clock) + 3)
    fill = max(1, fill)
    return (f'{C_BORDER}┌─ {RESET}{C_ACCENT}{BOLD}CALENDAR{RESET}'
            f'{C_BORDER} {"─" * fill} {RESET}{C_HI}{clock}{RESET}{C_BORDER} ─┐{RESET}')


def bottom_border(nxt=None):
    if not nxt:
        return f'{C_BORDER}└{"─" * (INNER + 2)}┘{RESET}'
    nxt = clip_w(nxt, 22)
    # └─ 次: <nxt> ──…──┘
    fill = OUTER - (7 + dwidth(nxt) + 1 + 1)
    fill = max(1, fill)
    return (f'{C_BORDER}└─ {RESET}{C_DIM}次:{RESET} {C_FG}{nxt}{RESET}'
            f'{C_BORDER} {"─" * fill}┘{RESET}')


def sep_row():
    return f'{C_BORDER}│ {"─" * INNER} │{RESET}'


def day_header(label, is_today):
    if is_today:
        return row([('▍', C_ACCENT), (label, C_ACCENT + BOLD)])
    return row([('▍', C_BORDER), (label, C_DIM + BOLD)])


def event_row(tlabel, summ, all_day):
    summ = clip_w(summ, INNER - 9)
    if all_day:
        return row([('  ', ''), ('◆', C_HI), (' 終日 ', C_DIM), (summ, C_FG)])
    return row([('  ', ''), (tlabel, C_CYAN), ('  ', ''), (summ, C_FG)])


def get_creds(do_auth):
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request

    creds = None
    if os.path.exists(TOKEN):
        creds = Credentials.from_authorized_user_file(TOKEN, SCOPES)
    if creds and creds.valid:
        return creds
    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            with open(TOKEN, 'w', encoding='utf-8') as f:
                f.write(creds.to_json())
            return creds
        except Exception:
            pass  # refresh 失敗 → 再認証へ
    if not do_auth:
        return None  # 未認証（ブラウザは開かない）
    if not os.path.exists(CLIENT):
        print("  client_secret.json が無い:")
        print("  " + CLIENT)
        sys.exit(1)
    from google_auth_oauthlib.flow import InstalledAppFlow
    flow = InstalledAppFlow.from_client_secrets_file(CLIENT, SCOPES)
    creds = flow.run_local_server(port=0)
    with open(TOKEN, 'w', encoding='utf-8') as f:
        f.write(creds.to_json())
    return creds


def render_card(now, body_rows, nxt=None):
    """ヘッダ + 本文 + フッタの枠を組んで出力する。"""
    print(top_border(f"{now:%H:%M}"))
    print(row([(f"{now:%m/%d (%a)}", C_DIM)]))
    print(row([('', '')]))
    for r in body_rows:
        print(r)
    print(bottom_border(nxt))


def msg_card(now, lines, color=C_DIM):
    body = [row([(clip_w(ln, INNER), color)]) for ln in lines]
    render_card(now, body)


def main():
    do_auth = '--auth' in sys.argv
    now = datetime.datetime.now().astimezone()

    creds = get_creds(do_auth)
    if not creds:
        msg_card(now, [
            '', '未認証です。初回だけ手動で:',
            'python ~/dotfiles/wezterm/gcal.py --auth',
        ], C_ERR)
        return

    from googleapiclient.discovery import build
    svc = build('calendar', 'v3', credentials=creds, cache_discovery=False)

    tmin = now.replace(hour=0, minute=0, second=0, microsecond=0)
    tmax = tmin + datetime.timedelta(days=DAYS)
    try:
        events = svc.events().list(
            calendarId='primary',
            timeMin=tmin.isoformat(), timeMax=tmax.isoformat(),
            singleEvents=True, orderBy='startTime', maxResults=MAXN,
        ).execute().get('items', [])
    except Exception as e:
        msg_card(now, ['', '取得エラー:', clip_w(str(e), INNER)], C_ERR)
        return

    # 日付ごとにまとめる + 次の予定(これから始まる最初のもの)を拾う
    days = OrderedDict()
    nxt = None
    for e in events:
        st = e['start']
        summ = e.get('summary', '(無題)')
        if 'date' in st and 'dateTime' not in st:                 # 終日
            d = datetime.date.fromisoformat(st['date'])
            days.setdefault(d, []).append((None, summ))
        else:
            dt = datetime.datetime.fromisoformat(
                st['dateTime'].replace('Z', '+00:00')).astimezone()
            days.setdefault(dt.date(), []).append((dt, summ))
            if nxt is None and dt >= now:
                nxt = f"{dt:%H:%M} {summ}"

    if not days:
        msg_card(now, ['', f'予定なし(今日〜{DAYS}日)'], C_DIM)
        return

    body = []
    first = True
    for d, items in days.items():
        if not first:
            body.append(row([('', '')]))   # 日付グループ間の空行
        first = False
        is_today = (d == now.date())
        # %-m/%-d は Windows の strftime で不可なので手組みする
        md = f"{d.month}/{d.day}"
        wd = WDAY[d.weekday()]
        if is_today:
            label = f"今日 {md} ({wd})"
        elif d == now.date() + datetime.timedelta(days=1):
            label = f"明日 {md} ({wd})"
        else:
            label = f"{md} ({wd})"
        body.append(day_header(label, is_today))
        for t, summ in items:
            tlabel = '' if t is None else f"{t:%H:%M}"
            body.append(event_row(tlabel, summ, t is None))

    render_card(now, body, nxt)


if __name__ == '__main__':
    main()
