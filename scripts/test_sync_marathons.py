#!/usr/bin/env python3
"""동기화 스크립트의 순수 함수 자체 점검. 네트워크·DB 없이 돈다.

    python3 scripts/test_sync_marathons.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import sync_marathons as sync


def test_upload_rows_have_identical_keys():
    """PostgREST 는 배열 안 객체 키가 다르면 배치 전체를 400 으로 튕긴다(PGRST102)."""
    rows = sync.rows_for_upload([
        {"name": "접수 중인 대회", "event_date": "2026-10-03", "status": "open", "fee_min": 30000},
        {"name": "정보가 적은 대회", "event_date": "2026-10-04"},
        {"name": "날짜 미정", "event_date": None, "image_url": "https://example.com/a.jpg"},
    ])
    assert {tuple(sorted(row)) for row in rows} == {tuple(sorted(sync.UPLOAD_COLUMNS))}, "행마다 키가 다르다"
    assert rows[1]["status"] is None and rows[1]["fee_min"] is None


def test_not_null_columns_get_defaults():
    """courses·tags·type 은 NOT NULL — None 으로 보내면 DB 가 거부한다."""
    row = sync.rows_for_upload([{"name": "빈 대회", "event_date": "2026-10-03"}])[0]
    assert row["courses"] == [] and row["tags"] == [] and row["type"] == "대회"


def test_detail_page_parsing():
    """상세 페이지에서 포스터·접수기간·참가비를 뽑는다."""
    html = ('<meta property="og:image" content="https://res.cloudinary.com/x/image/upload/v1/poster.jpg"/>'
            '접수기간</p><p class="x">2026.07.10<span class="y">~</span>2026.07.30</p>'
            '<span>5km</span><span>35,000<!-- -->원</span><span>30,000<!-- -->원</span>')
    detail = sync.parse_detail(html)
    assert detail["image_url"] == \
        "https://res.cloudinary.com/x/image/upload/w_800,f_auto,q_auto:good/v1/poster.jpg"
    assert detail["reg_start_date"] == "2026-07-10" and detail["reg_end_date"] == "2026-07-30"
    assert detail["fee_min"] == 30000
    assert sync.parse_detail("<html>아무것도 없음</html>") == {}


def test_classification_and_tags():
    assert sync.classify("2026 춘천마라톤") == "대회"
    assert sync.classify("카카오프렌즈 런") == "테마런"
    assert "야간" in sync.tags_for("2026 잠수교 10K 나이트런", [])
    assert "풀코스" in sync.tags_for("공주백제마라톤", ["10km", "Full"])


if __name__ == "__main__":
    for name, test in sorted(globals().items()):
        if name.startswith("test_"):
            test()
            print(f"  ✓ {name}")
    print("통과")
