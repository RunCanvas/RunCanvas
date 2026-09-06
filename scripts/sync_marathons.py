#!/usr/bin/env python3
"""국내 마라톤·러닝 이벤트 일정을 모아 Supabase `marathon_events` 에 넣는다.

앱에 JSON을 박아 두면 일정 하나 바꾸는 데 앱 심사를 다시 받아야 하므로,
데이터는 서버에 두고 이 스크립트가 주기적으로 갱신한다(GitHub Actions).

출처
  1) 공공데이터포털 · 문화체육관광부_국내마라톤대회 정보 (CSV, 인증 불필요)
  2) kormarathon.com 월별 페이지에 서버 렌더링된 이벤트 JSON

환경변수 (GitHub Actions secrets)
  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   ← 업로드에 필요. 없으면 --dry-run 만 가능
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import os
import sys
import re
import urllib.request
from html import unescape
from datetime import date, timedelta

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) RunCanvas-schedule-sync"
OFFICIAL_CSV = ("https://www.data.go.kr/cmm/cmm/fileDownload.do"
                "?atchFileId=FILE_000000003607547&fileDetailSn=1&insertDataPrcus=N")
KORMARATHON_MONTH = "https://www.kormarathon.com/ko/marathons/{year}/{month:02d}"


def fetch(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


# ---------------------------------------------------------------- 출처 1: 공공데이터포털

def from_official() -> list[dict]:
    try:
        text = fetch(OFFICIAL_CSV).decode("utf-8-sig")
    except Exception as error:                      # 원본이 내려가도 전체 동기화는 계속한다
        print(f"[경고] 공공데이터 CSV 실패: {error}", file=sys.stderr)
        return []
    events = []
    for row in csv.DictReader(io.StringIO(text)):
        name = (row.get("대회명") or "").strip()
        if not name:
            continue
        events.append({
            "name": name,
            "event_date": (row.get("대회일시") or "").strip() or None,
            "region": None,
            "place": (row.get("대회장소") or "").strip() or None,
            "courses": [c.strip() for c in (row.get("종목") or "").split(",") if c.strip()],
            "source": "공공데이터포털(문화체육관광부)",
        })
    return events


# ---------------------------------------------------------------- 출처 2: kormarathon

def from_kormarathon(months: int) -> list[dict]:
    """월별 페이지에 서버 렌더링된 `"events":[...]` 배열을 그대로 읽는다.

    HTML 구조를 긁는 것보다 안정적이지만, 사이트가 바꾸면 깨질 수 있다 →
    한 달이 실패해도 나머지는 계속 진행하고, 전체가 0건이면 호출한 쪽이 실패로 처리한다.
    """
    events: list[dict] = []
    cursor = date.today().replace(day=1)
    misses = 0
    for _ in range(months):
        url = KORMARATHON_MONTH.format(year=cursor.year, month=cursor.month)
        try:
            raw = fetch(url).decode("utf-8", errors="replace")
            found = parse_kormarathon(raw)
            events += found
            misses = 0 if found else misses + 1
        except Exception as error:
            print(f"[안내] {url}: {error}", file=sys.stderr)
            misses += 1
        # 아직 등록이 안 된 먼 미래 달이 이어지면 그만 둔다
        if misses >= 2:
            break
        cursor = (cursor + timedelta(days=32)).replace(day=1)
    return events


CARD_RE = re.compile(r'<a class="group block.*?</a>', re.S)
TITLE_RE = re.compile(r'group-hover:text-blue-700[^>]*>([^<]+)</div>')
DATE_RE = re.compile(r'<span class="hidden md:inline">(\d{4})\.(\d{2})\.(\d{2})</span>')
HREF_RE = re.compile(r'href="(/ko/[a-z]+/[^"]+)"')
PLACE_RE = re.compile(r'text-gray-600[^>]*>\s*<span>([^<]*)</span>.*?break-words">([^<]*)</span>', re.S)
COURSE_RE = re.compile(r'text-sm font-semibold text-gray-800[^>]*>([^<]+)</div>')
STATUS_RE = re.compile(r'ring-1[^>]*>([^<]{1,8})</span>')

STATUS_MAP = {"마감": "closed", "접수중": "open", "접수 중": "open", "예정": "scheduled", "오픈예정": "scheduled"}


def parse_kormarathon(html: str) -> list[dict]:
    """월별 페이지의 이벤트 카드를 읽는다.

    페이지 안 JSON 배열에는 앞쪽 몇 건만 들어 있어서(하이드레이션용) 그걸 쓰면 대부분을 놓친다.
    서버가 렌더링해 둔 카드 마크업이 전부를 담고 있으므로 그쪽을 읽는다.
    """
    events = []
    for card in CARD_RE.findall(html):
        title = TITLE_RE.search(card)
        date_match = DATE_RE.search(card)
        if not title or not date_match:
            continue

        place_match = PLACE_RE.search(card)
        course_match = COURSE_RE.search(card)
        href_match = HREF_RE.search(card)
        status_match = STATUS_RE.search(card)

        courses = []
        if course_match:
            courses = [c.strip() for c in course_match.group(1).split(",") if c.strip()]

        events.append({
            "name": unescape(title.group(1)).strip(),
            "event_date": "-".join(date_match.groups()),
            "region": unescape(place_match.group(1)).strip() if place_match else None,
            "place": unescape(place_match.group(2)).strip() if place_match else None,
            "courses": courses,
            "status": STATUS_MAP.get(status_match.group(1).strip()) if status_match else None,
            "signup_url": f"https://www.kormarathon.com{href_match.group(1)}" if href_match else None,
            "source": "kormarathon.com",
        })
    return events


# ---------------------------------------------------------------- 출처 2-b: 대회 상세 페이지

# 월별 목록에는 포스터·접수기간·참가비가 없다. 상세 페이지에서만 가져올 수 있다.
POSTER_RE = re.compile(r'<meta property="og:image" content="([^"]+)"')
PERIOD_RE = re.compile(r'접수기간</p><p[^>]*>(\d{4})\.(\d{2})\.(\d{2})<span[^>]*>~</span>(\d{4})\.(\d{2})\.(\d{2})')
FEE_RE = re.compile(r'>([\d,]+)<!-- -->원<')
DETAIL_KEYS = ("image_url", "reg_start_date", "reg_end_date", "fee_min")


def poster_url(url: str) -> str:
    """Cloudinary 원본은 1200px 넘는 것도 있다 → 폰 카드에 맞게 폭 800으로 줄여 받는다."""
    marker = "/image/upload/"
    if "res.cloudinary.com" in url and marker in url:
        return url.replace(marker, marker + "w_800,f_auto,q_auto:good/", 1)
    return url


def parse_detail(html: str) -> dict:
    """상세 페이지에서 포스터·접수기간·참가비(최저)를 뽑는다. 없는 항목은 그냥 빠진다."""
    detail: dict = {}
    poster = POSTER_RE.search(html)
    if poster:
        detail["image_url"] = poster_url(unescape(poster.group(1)))
    period = PERIOD_RE.search(html)
    if period:
        detail["reg_start_date"] = "-".join(period.groups()[:3])
        detail["reg_end_date"] = "-".join(period.groups()[3:])
    fees = [int(fee.replace(",", "")) for fee in FEE_RE.findall(html)]
    if fees:
        detail["fee_min"] = min(fees)
    return detail


def add_details(events: list[dict], known: dict) -> None:
    """대회마다 상세 페이지를 한 번씩 읽어 채운다.

    이미 DB에 포스터가 있는 대회는 건너뛴다 — 안 그러면 6시간마다 200번씩 남의 사이트를 긁는다.
    상세가 없어도 목록은 나와야 하므로 실패는 조용히 넘긴다.
    """
    fetched = 0
    for event in events:
        cached = known.get((event["name"], event.get("event_date")), {})
        if cached.get("image_url"):
            event.update({key: cached[key] for key in DETAIL_KEYS if cached.get(key) is not None})
            continue
        url = event.get("signup_url")
        if not url:
            continue
        try:
            event.update(parse_detail(fetch(url).decode("utf-8", errors="replace")))
            fetched += 1
        except Exception as error:
            print(f"[안내] 상세 실패 {url}: {error}", file=sys.stderr)
    print(f"상세 페이지 {fetched}건 조회 (나머지는 이미 받아 둔 값 재사용)")


def known_details() -> dict:
    """DB에 이미 있는 상세값 — 없으면 빈 dict(전부 새로 받는다)."""
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        return {}
    endpoint = f"{url.rstrip('/')}/rest/v1/marathon_events?select=name,event_date,{','.join(DETAIL_KEYS)}"
    request = urllib.request.Request(endpoint, headers={"apikey": key, "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            rows = json.loads(response.read())
    except Exception as error:
        print(f"[경고] 기존 상세 조회 실패: {error}", file=sys.stderr)
        return {}
    return {(row["name"], row.get("event_date")): row for row in rows}


# ---------------------------------------------------------------- 정규화

THEME_HINTS = ("런", "RUN", "Run", "레이스", "Race", "페스타")


def classify(name: str) -> str:
    """대회(기록 중심) vs 테마런(브랜드·캐릭터·야간런 등). 이름 기준 근사치."""
    if "마라톤" in name or "로드레이스" in name:
        return "대회"
    if any(hint in name for hint in THEME_HINTS):
        return "테마런"
    return "대회"


def tags_for(name: str, courses: list[str]) -> list[str]:
    tags = []
    lowered = name.lower()
    if any(k in name for k in ("나이트", "야간", "문라이트")) or "night" in lowered:
        tags.append("야간")
    if any(k in name for k in ("기부", "나눔", "돕기", "평화", "인권", "봉사", "사랑")):
        tags.append("기부·공익")
    if "펫" in name:
        tags.append("펫")
    if "Full" in courses or "풀" in " ".join(courses):
        tags.append("풀코스")
    return tags


def normalize(events: list[dict]) -> list[dict]:
    """이름+날짜로 중복 제거. 항목이 더 많은 쪽(=kormarathon)을 남긴다."""
    merged: dict[tuple, dict] = {}
    for event in events:
        key = (event["name"], event.get("event_date"))
        event = dict(event)
        event["type"] = classify(event["name"])
        event["tags"] = tags_for(event["name"], event.get("courses") or [])
        existing = merged.get(key)
        if existing is None or _richness(event) > _richness(existing):
            merged[key] = event
    return sorted(merged.values(), key=lambda e: (e.get("event_date") or "9999-99-99", e["name"]))


def _richness(event: dict) -> int:
    return sum(1 for value in event.values() if value not in (None, "", [], {}))


# ---------------------------------------------------------------- 업로드

def upload(events: list[dict]) -> None:
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise SystemExit("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 가 필요합니다 (--dry-run 으로 확인만 가능)")

    endpoint = f"{url.rstrip('/')}/rest/v1/marathon_events?on_conflict=name,event_date"
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    # 한 번에 다 보내면 실패했을 때 원인을 못 찾는다 → 50건씩
    for start in range(0, len(events), 50):
        chunk = events[start:start + 50]
        body = json.dumps(chunk, ensure_ascii=False).encode()
        request = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
        with urllib.request.urlopen(request, timeout=60) as response:
            print(f"  {start + 1}~{start + len(chunk)}번 → HTTP {response.status}")


def purge_past() -> None:
    """이미 끝난 대회는 지운다. 앱은 다가오는 일정만 보여주므로 계속 쌓아둘 이유가 없다."""
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        return
    endpoint = f"{url.rstrip('/')}/rest/v1/marathon_events?event_date=lt.{date.today().isoformat()}"
    headers = {"apikey": key, "Authorization": f"Bearer {key}", "Prefer": "return=minimal"}
    request = urllib.request.Request(endpoint, headers=headers, method="DELETE")
    with urllib.request.urlopen(request, timeout=60) as response:
        print(f"  지난 일정 삭제 → HTTP {response.status}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--months", type=int, default=8, help="이번 달부터 몇 달치를 볼지")
    parser.add_argument("--dry-run", action="store_true", help="업로드하지 않고 결과만 출력")
    parser.add_argument("--no-details", action="store_true",
                        help="상세 페이지(포스터·접수기간·참가비)를 읽지 않는다 — 빠르게 목록만 볼 때")
    parser.add_argument("--out", help="정규화 결과를 JSON 파일로도 저장(앱 번들 씨앗 갱신용)")
    args = parser.parse_args()

    official = from_official()
    community = from_kormarathon(args.months)
    print(f"공공데이터 {len(official)}건 / kormarathon {len(community)}건")
    if not community and not official:
        raise SystemExit("두 출처 모두 0건 — 원본이 바뀌었을 수 있습니다. 파서를 확인하세요.")

    events = normalize(official + community)
    # 끝난 일정은 담지 않는다 — 목록에서도 DB에서도 지운다. 날짜 미정(None)은 남긴다.
    today = date.today().isoformat()
    dropped = [e for e in events if (e.get("event_date") or today) < today]
    events = [e for e in events if (e.get("event_date") or today) >= today]
    print(f"정규화 {len(events)}건 (지난 일정 {len(dropped)}건 제외)")

    if not args.no_details:
        add_details(events, known_details())

    if args.out:
        with open(args.out, "w", encoding="utf-8") as file:
            json.dump({"updatedAt": date.today().isoformat(), "events": events},
                      file, ensure_ascii=False, indent=2)
        print(f"씨앗 JSON 저장: {args.out}")

    if args.dry_run:
        for event in events[:5]:
            print(" ", event["event_date"], event["type"], event["name"])
        return
    upload(events)
    purge_past()
    print("업로드 완료")


if __name__ == "__main__":
    main()
