#!/usr/bin/env python3
"""국내 마라톤·러닝 이벤트 일정을 모아 Supabase `marathon_events` 에 넣는다.

앱에 JSON을 박아 두면 일정 하나 바꾸는 데 앱 심사를 다시 받아야 하므로,
데이터는 서버에 두고 이 스크립트가 주기적으로 갱신한다(GitHub Actions).

출처
  kormarathon.com 월별 목록(서버 렌더링 카드) + 대회 상세 페이지(포스터·접수기간·참가비)
  공공데이터포털 CSV 는 2024년 자료에서 갱신이 멈췄고 GitHub 러너에서 매번 타임아웃이라 뺐다.

환경변수 (GitHub Actions secrets)
  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   ← 업로드에 필요. 없으면 --dry-run 만 가능
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import re
import urllib.error
import urllib.parse
import urllib.request
from html import unescape
from datetime import date, datetime, timedelta, timezone

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) RunCanvas-schedule-sync"
KORMARATHON_MONTH = "https://www.kormarathon.com/ko/marathons/{year}/{month:02d}"


def fetch(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


# ---------------------------------------------------------------- 수집: kormarathon 월별 목록

def from_kormarathon(months: int) -> tuple[list[dict], date | None]:
    """월별 페이지에 서버 렌더링된 `"events":[...]` 배열을 그대로 읽는다.

    HTML 구조를 긁는 것보다 안정적이지만, 사이트가 바꾸면 깨질 수 있다 →
    한 달이 실패해도 나머지는 계속 진행하고, 전체가 0건이면 호출한 쪽이 실패로 처리한다.

    함께 돌려주는 날짜는 실제로 이벤트를 읽어 낸 마지막 달의 말일 — 그 날까지는
    "이번 실행에서 못 본 행 = 원본에서 사라진 행" 으로 믿고 지워도 된다(purge_stale).
    """
    events: list[dict] = []
    cursor = date.today().replace(day=1)
    misses = 0
    seen_until: date | None = None
    contiguous = True
    for _ in range(months):
        url = KORMARATHON_MONTH.format(year=cursor.year, month=cursor.month)
        next_month = (cursor + timedelta(days=32)).replace(day=1)
        try:
            raw = fetch(url).decode("utf-8", errors="replace")
            found = parse_kormarathon(raw)
            events += found
            misses = 0 if found else misses + 1
            if found and contiguous:
                seen_until = next_month - timedelta(days=1)
            elif not found:
                # 왜: 한 달을 못 읽고 그 뒤 달을 읽었다고 삭제 범위를 뒤로 늘리면,
                # 비어 있던 달의 정상 DB 행까지 '원본에서 사라짐'으로 오판한다.
                contiguous = False
        except Exception as error:
            print(f"[안내] {url}: {error}", file=sys.stderr)
            misses += 1
            contiguous = False
        # 아직 등록이 안 된 먼 미래 달이 이어지면 그만 둔다
        if misses >= 2:
            break
        cursor = next_month
    return events, seen_until


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


# ---------------------------------------------------------------- 수집: 대회 상세 페이지

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
    """대회마다 상세 페이지를 읽어 채운다.

    DB에 포스터가 있고 접수 중이 아닌 대회는 건너뛴다 — 안 그러면 6시간마다 200번씩 남의 사이트를 긁는다.
    접수 중인 대회는 매번 다시 읽는다: 접수 연장·조기마감·참가비 변경은 상세에만 있어서, 한 번 읽은
    마감일을 계속 쓰면 목록에서 온 '접수 중' 과 이미 지난 마감일이 카드에 같이 보인다.
    상세가 없어도 목록은 나와야 하므로 실패는 조용히 넘긴다.
    """
    fetched = 0
    for event in events:
        cached = known.get((event["name"], event.get("event_date")), {})
        # 왜: DB 값을 먼저 깔아 둔다 — 재조회가 실패하거나 일부만 파싱돼도 업서트가 기존 값을 NULL 로 덮지 않게
        event.update({key: cached[key] for key in DETAIL_KEYS if cached.get(key) is not None})
        if cached.get("image_url") and event.get("status") != "open":
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
    """DB에 이미 있는 상세값 — 자격증명이 없으면 빈 dict(전부 새로 받는다)."""
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
        # 왜: 여기서 빈 dict 로 넘어가면 곧 같은 DB 에 업서트하면서, 상세 재조회에 실패한 대회의
        # 포스터·마감일을 NULL 로 덮는다. 읽기가 안 되는 DB 에는 쓰지 않는다.
        raise SystemExit(f"기존 상세 조회 실패: {error} — 다음 실행에서 다시 시도합니다")
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

# PostgREST 는 한 배열 안 객체들의 키가 전부 같아야 받는다(PGRST102 "All object keys must match").
# 접수 상태·참가비처럼 있는 대회만 있는 항목 때문에 키가 들쭉날쭉하면 배치 전체가 400 으로 튕긴다.
UPLOAD_COLUMNS = ("name", "event_date", "region", "place", "courses", "type", "tags", "status",
                  "signup_url", "source", "image_url", "reg_start_date", "reg_end_date", "fee_min",
                  "updated_at")


def rows_for_upload(events: list[dict], synced_at: str | None = None) -> list[dict]:
    """모든 행을 같은 키로 맞춘다. 빠진 칸은 None, NOT NULL 인 칸은 기본값으로.

    `updated_at` 은 직접 넣는다 — 업서트로 갱신될 때는 컬럼 기본값 now() 가 다시 적용되지 않아서,
    안 넣으면 이 값이 "마지막 동기화"가 아니라 "처음 들어온 시각"으로 남는다.
    """
    synced_at = synced_at or datetime.now(timezone.utc).isoformat()
    rows = []
    for event in events:
        row = {column: event.get(column) for column in UPLOAD_COLUMNS}
        row["courses"] = row["courses"] or []
        row["tags"] = row["tags"] or []
        row["type"] = row["type"] or "대회"
        row["updated_at"] = synced_at
        rows.append(row)
    return rows


def upload(events: list[dict]) -> str:
    """업서트하고, 모든 행에 찍은 `updated_at`(이번 동기화 시각)을 돌려준다 — purge_stale 의 기준."""
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
    synced_at = datetime.now(timezone.utc).isoformat()
    rows = rows_for_upload(events, synced_at)
    # 한 번에 다 보내면 실패했을 때 원인을 못 찾는다 → 50건씩
    for start in range(0, len(rows), 50):
        chunk = rows[start:start + 50]
        body = json.dumps(chunk, ensure_ascii=False).encode()
        request = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                print(f"  {start + 1}~{start + len(chunk)}번 → HTTP {response.status}")
        except urllib.error.HTTPError as error:
            # PostgREST 는 본문에 원인을 적어 준다 — 이걸 안 찍으면 로그에 400 만 남는다
            print(f"[오류] {start + 1}~{start + len(chunk)}번: {error.read().decode('utf-8', 'replace')}",
                  file=sys.stderr)
            raise
    return synced_at


def purge_stale(synced_at: str, seen_until: date | None) -> None:
    """이번 실행에서 못 본 kormarathon 행을 지운다 — 연기·개명·취소된 대회의 옛 행이 앱에 두 번 보이지 않게.

    업서트는 (name, event_date) 로만 맞추므로 날짜나 이름이 바뀌면 옛 행이 그대로 남고, 그 행의
    status 는 다시 갱신되지 않아 '접수 중' 으로 굳는다. 원본을 끝까지 못 읽은 실행(사이트 장애로
    일찍 끊김)이 멀쩡한 미래 일정을 지우지 않도록, 실제로 읽어 낸 마지막 달(seen_until)까지만 지운다.
    upload 가 성공한 뒤에만 부른다 — 업서트가 실패했으면 '못 본 행' 을 가릴 수 없다.
    """
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key or seen_until is None:
        return
    # 왜: synced_at 의 '+00:00' 이 그대로 URL 에 들어가면 공백으로 읽혀 필터가 깨진다 → 인코딩
    query = urllib.parse.urlencode({
        "source": "eq.kormarathon.com",
        "updated_at": f"lt.{synced_at}",
        "event_date": f"lte.{seen_until.isoformat()}",
    })
    endpoint = f"{url.rstrip('/')}/rest/v1/marathon_events?{query}"
    headers = {"apikey": key, "Authorization": f"Bearer {key}", "Prefer": "return=minimal"}
    request = urllib.request.Request(endpoint, headers=headers, method="DELETE")
    with urllib.request.urlopen(request, timeout=60) as response:
        print(f"  원본에서 사라진 일정 삭제({seen_until.isoformat()} 까지) → HTTP {response.status}")


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

    community, seen_until = from_kormarathon(args.months)
    print(f"kormarathon {len(community)}건")
    if not community:
        raise SystemExit("수집 0건 — 원본이 바뀌었을 수 있습니다. 파서를 확인하세요.")

    events = normalize(community)
    # 끝난 일정은 담지 않는다 — 목록에서도 DB에서도 지운다. 날짜 미정(None)은 남긴다.
    today = date.today().isoformat()
    dropped = [e for e in events if (e.get("event_date") or today) < today]
    events = [e for e in events if (e.get("event_date") or today) >= today]
    print(f"정규화 {len(events)}건 (지난 일정 {len(dropped)}건 제외)")

    if not args.no_details:
        add_details(events, known_details())

    if args.out:
        with open(args.out, "w", encoding="utf-8") as file:
            # 왜: updatedAt(오늘 날짜)을 넣으면 일정이 하나도 안 바뀐 날에도 파일이 달라져
            # 워크플로의 `git diff --quiet` 가 매일 봇 커밋을 쌓는다. 앱은 events 만 읽는다.
            json.dump({"events": events}, file, ensure_ascii=False, indent=2)
        print(f"씨앗 JSON 저장: {args.out}")

    if args.dry_run:
        for event in events[:5]:
            print(" ", event["event_date"], event["type"], event["name"])
        return
    synced_at = upload(events)
    purge_stale(synced_at, seen_until)
    purge_past()
    print("업로드 완료")


if __name__ == "__main__":
    main()
