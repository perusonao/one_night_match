#!/usr/bin/env python3
"""
ファイプロワールドFAQまとめ Wiki* の「技データ表」ページから
全テーブルデータを取得してファイルに出力するスクリプト。

対象例:
  https://wikiwiki.jp/fireprow/技関連/技データ表１
  https://wikiwiki.jp/fireprow/技関連/技データ表２

使い方（ローカル環境で実行）:
  pip install requests beautifulsoup4
  python scrape_fireprow.py

出力:
  ./out/ 以下に、ページ内の各テーブルを CSV・JSON、
  および全テーブルをまとめた Markdown で保存します。
"""

import csv
import json
import re
import sys
import time
from pathlib import Path

import requests
from bs4 import BeautifulSoup

# 取得対象ページ（必要に応じて追加・変更してください）
PAGES = {
    "技データ表1": "https://wikiwiki.jp/fireprow/技関連/技データ表１",
    "技データ表2": "https://wikiwiki.jp/fireprow/技関連/技データ表２",
    "技データ表3": "https://wikiwiki.jp/fireprow/技関連/技データ表３",
}

OUT_DIR = Path("out")

# ブラウザに近い User-Agent（bot 対策の 403 回避のため）
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/125.0 Safari/537.36"
    ),
    "Accept-Language": "ja,en;q=0.8",
}


def fetch(url: str) -> str:
    """ページHTMLを取得。"""
    resp = requests.get(url, headers=HEADERS, timeout=30)
    resp.raise_for_status()
    resp.encoding = resp.apparent_encoding or "utf-8"
    return resp.text


def cell_text(cell) -> str:
    """セル内テキストを整形（<br>を改行に、余分な空白を圧縮）。"""
    for br in cell.find_all("br"):
        br.replace_with("\n")
    text = cell.get_text()
    # 行内の連続空白のみ圧縮し、改行は維持
    lines = [re.sub(r"[ \t　]+", " ", ln).strip() for ln in text.split("\n")]
    return "\n".join(ln for ln in lines if ln != "").strip()


def parse_table(table) -> list[list[str]]:
    """<table> を2次元リストに変換。"""
    rows = []
    for tr in table.find_all("tr"):
        cells = tr.find_all(["th", "td"])
        if not cells:
            continue
        rows.append([cell_text(c) for c in cells])
    return rows


def extract_tables(html: str) -> list[list[list[str]]]:
    """本文中の全テーブルを抽出。"""
    soup = BeautifulSoup(html, "html.parser")
    # wikiwiki の本文領域に絞る（見つからなければ全体から）
    body = soup.select_one("#body, .wikibody, #content, article") or soup
    tables = body.find_all("table")
    result = []
    for t in tables:
        rows = parse_table(t)
        # 空テーブル・レイアウト用テーブルを除外
        if rows and any(len(r) > 1 for r in rows):
            result.append(rows)
    return result


def slugify(name: str) -> str:
    return re.sub(r"[^\w\-一-龠ぁ-んァ-ヶ０-９]+", "_", name).strip("_")


def save_table(base: Path, page_name: str, idx: int, rows: list[list[str]]) -> None:
    stem = f"{slugify(page_name)}_table{idx:02d}"

    # CSV
    with (base / f"{stem}.csv").open("w", encoding="utf-8-sig", newline="") as f:
        csv.writer(f).writerows(rows)

    # JSON（1行目をヘッダーとして辞書化。列数が揃わない行は配列のまま保持）
    header = rows[0]
    records = []
    for r in rows[1:]:
        if len(r) == len(header):
            records.append(dict(zip(header, r)))
        else:
            records.append(r)
    with (base / f"{stem}.json").open("w", encoding="utf-8") as f:
        json.dump(
            {"page": page_name, "header": header, "rows": records},
            f, ensure_ascii=False, indent=2,
        )


def rows_to_markdown(rows: list[list[str]]) -> str:
    width = max(len(r) for r in rows)
    norm = [r + [""] * (width - len(r)) for r in rows]
    esc = lambda s: s.replace("\n", "<br>").replace("|", "\\|")
    out = ["| " + " | ".join(esc(c) for c in norm[0]) + " |"]
    out.append("| " + " | ".join(["---"] * width) + " |")
    for r in norm[1:]:
        out.append("| " + " | ".join(esc(c) for c in r) + " |")
    return "\n".join(out)


def main() -> int:
    OUT_DIR.mkdir(exist_ok=True)
    md_parts: list[str] = ["# ファイプロ 技データ表\n"]

    for page_name, url in PAGES.items():
        print(f"取得中: {page_name} <- {url}")
        try:
            html = fetch(url)
        except Exception as e:  # noqa: BLE001
            print(f"  失敗: {e}", file=sys.stderr)
            continue

        tables = extract_tables(html)
        print(f"  テーブル数: {len(tables)}")
        md_parts.append(f"\n## {page_name}\n\n出典: {url}\n")

        for idx, rows in enumerate(tables, 1):
            save_table(OUT_DIR, page_name, idx, rows)
            md_parts.append(f"\n### {page_name} - table {idx}\n")
            md_parts.append(rows_to_markdown(rows))
            print(f"  table {idx}: {len(rows)} 行 x {max(len(r) for r in rows)} 列")

        time.sleep(1)  # サーバー負荷軽減

    (OUT_DIR / "技データ表_all.md").write_text("\n".join(md_parts), encoding="utf-8")
    print(f"\n完了。出力先: {OUT_DIR.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
