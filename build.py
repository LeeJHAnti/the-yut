#!/usr/bin/env python3
"""
The Yut — 통합 빌드 스크립트
Godot Web 내보내기 → AdSense 삽입 → 완료

사용법:
  python build.py                Godot 빌드 + AdSense 삽입 (기본)
  python build.py --ads-only     AdSense만 재삽입 (빌드 스킵)
  python build.py --godot PATH   Godot 실행 파일 경로 직접 지정
"""

import sys
import shutil
import subprocess
from pathlib import Path

# ═══════════════════════════════════════════
#  경로 설정
# ═══════════════════════════════════════════
ROOT = Path(__file__).resolve().parent
CLIENT_DIR = ROOT / "the-yut-client"
STATIC_DIR = ROOT / "the-yut-server" / "static"
OUTPUT_HTML = STATIC_DIR / "index.html"

# ═══════════════════════════════════════════
#  AdSense 설정
# ═══════════════════════════════════════════
AD_CLIENT = "ca-pub-6672065155865292"
AD_SLOT = "3007482495"

# ═══════════════════════════════════════════
#  삽입할 코드 조각
# ═══════════════════════════════════════════

ADSENSE_HEAD_SCRIPT = (
    f'\t<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'
    f'?client={AD_CLIENT}"\n\t\tcrossorigin="anonymous"></script>'
)

ADSENSE_CSS = """\
/* ── Ad layout ── */
#ad-top {
\twidth: 100%;
\tmax-width: 728px;
\ttext-align: center;
\tflex-shrink: 0;
\toverflow: hidden;
\tz-index: 10;
}
/* Collapse ad container when empty (no min-height!) */
#ad-top:empty,
#ad-top .adsbygoogle[data-ad-status="unfilled"] {
\tdisplay: none !important;
}

#game-container {
\tflex: 1 1 0;
\twidth: 100%;
\tdisplay: flex;
\tjustify-content: center;
\talign-items: center;
\tposition: relative;
\toverflow: hidden;
\tmin-height: 0;
}

/* ── Mobile: hide ad on short screens to prevent game cutoff ── */
@media (max-height: 600px) {
\t#ad-top { display: none !important; }
}
/* ── Desktop: constrain ad height ── */
@media (min-height: 601px) {
\t#ad-top {
\t\tmax-height: 100px;
\t}
}"""

AD_BANNER_DIV = (
    '\t\t<div id="ad-top">\n'
    '\t\t\t<ins class="adsbygoogle"\n'
    '\t\t\t\tstyle="display:block"\n'
    f'\t\t\t\tdata-ad-client="{AD_CLIENT}"\n'
    f'\t\t\t\tdata-ad-slot="{AD_SLOT}"\n'
    '\t\t\t\tdata-ad-format="auto"\n'
    '\t\t\t\tdata-full-width-responsive="true"></ins>\n'
    '\t\t\t<script>(adsbygoogle = window.adsbygoogle || []).push({});</script>\n'
    '\t\t</div>'
)

SEO_META = '<meta name="description" content="Play Yutnori online! A traditional Korean board game with cute pixel art.">'


# ═══════════════════════════════════════════
#  Step 1: Godot 내보내기
# ═══════════════════════════════════════════

def find_godot(user_path: str | None) -> str:
    """Godot 실행 파일을 찾는다."""
    # 1) 사용자가 직접 지정
    if user_path:
        p = Path(user_path)
        if p.is_file():
            return str(p)
        print(f"  ERROR: 지정한 경로에 Godot가 없습니다: {user_path}")
        sys.exit(1)

    # 2) PATH에서 찾기
    for name in ["godot", "godot4", "Godot"]:
        found = shutil.which(name)
        if found:
            return found

    # 3) 일반적인 Windows 경로
    win_paths = [
        Path.home() / "AppData" / "Local" / "Godot",
        Path("C:/Program Files/Godot"),
        Path("C:/Program Files (x86)/Godot"),
    ]
    for wp in win_paths:
        if wp.exists():
            for exe in wp.rglob("Godot*.exe"):
                return str(exe)
            for exe in wp.rglob("godot*.exe"):
                return str(exe)

    return ""


def run_godot_export(godot_cmd: str) -> None:
    """Godot Web 빌드 실행."""
    print(f"  Godot: {godot_cmd}")
    print(f"  프로젝트: {CLIENT_DIR}")
    print(f"  출력: {OUTPUT_HTML}")
    print()

    result = subprocess.run(
        [godot_cmd, "--headless", "--export-release", "Web", str(OUTPUT_HTML)],
        cwd=str(CLIENT_DIR),
        capture_output=True,
        text=True,
    )

    # Godot은 경고를 stderr로 보내지만 성공할 수 있음
    if result.returncode != 0:
        print(f"  ERROR: Godot 빌드 실패 (exit code {result.returncode})")
        if result.stderr:
            # 마지막 20줄만 출력
            lines = result.stderr.strip().split("\n")
            for line in lines[-20:]:
                print(f"    {line}")
        sys.exit(1)

    if not OUTPUT_HTML.exists():
        print("  ERROR: 빌드는 성공했지만 index.html이 생성되지 않았습니다.")
        sys.exit(1)

    print("  Godot 빌드 완료!")


# ═══════════════════════════════════════════
#  Step 2: AdSense + SEO 삽입
# ═══════════════════════════════════════════

def inject_adsense() -> None:
    """빌드된 index.html에 AdSense, 레이아웃 CSS, SEO 메타를 삽입."""
    if not OUTPUT_HTML.exists():
        print(f"  ERROR: {OUTPUT_HTML} 파일을 찾을 수 없습니다.")
        sys.exit(1)

    html = OUTPUT_HTML.read_text(encoding="utf-8")

    # 이미 삽입 완료?
    if AD_CLIENT in html:
        print("  AdSense가 이미 삽입되어 있습니다. 스킵합니다.")
        return

    original_len = len(html)

    # (1) <head>: AdSense 스크립트 삽입 — <style> 바로 앞
    marker = "\t\t<style>"
    if marker in html:
        html = html.replace(
            marker,
            f"\t<!-- Google AdSense -->\n{ADSENSE_HEAD_SCRIPT}\n\n{marker}",
            1,
        )

    # (2) CSS: 광고 레이아웃 스타일 삽입 — </style> 바로 앞
    marker = "\t\t</style>"
    if marker in html:
        html = html.replace(marker, f"\n{ADSENSE_CSS}\n{marker}", 1)

    # (3a) html, body에 width/height: 100% 추가 (flex 레이아웃에 필수)
    if "width: 100%;\n\theight: 100%;" not in html:
        for reset_target in ["html, body, #canvas {", "html, body {"]:
            if reset_target in html:
                html = html.replace(
                    reset_target,
                    reset_target + "\n\twidth: 100%;\n\theight: 100%;",
                    1,
                )
                break

    # (3b) body CSS: flexbox 추가
    # Godot의 body 스타일 블록에 flex 레이아웃 삽입
    # 주의: #status 등 다른 요소에도 flex가 있으므로 body 블록만 정확히 매칭
    import re as _re
    body_match = _re.search(r'body\s*\{[^}]*?overflow:\s*hidden;', html)
    if body_match and "display: flex" not in body_match.group():
        old_body = body_match.group()
        new_body = old_body.replace(
            "overflow: hidden;",
            "overflow: hidden;\n\tdisplay: flex;\n\tflex-direction: column;\n\talign-items: center;",
        )
        # 배경색도 어둡게 통일
        new_body = _re.sub(r'background-color:\s*[^;]+;', 'background-color: #1a1a1a;', new_body)
        html = html.replace(old_body, new_body, 1)

    # (3c) COEP 비활성화 — 스레드 미사용 시 불필요하고 AdSense를 차단함
    html = html.replace(
        '"ensureCrossOriginIsolationHeaders":true',
        '"ensureCrossOriginIsolationHeaders":false',
    )

    # (4) <body>: 광고 배너 div + game-container 래퍼 삽입
    if '<div id="ad-top">' not in html:
        body_marker = "<body>"
        if body_marker in html:
            html = html.replace(
                body_marker,
                f"{body_marker}\n{AD_BANNER_DIV}\n\n\t\t<div id=\"game-container\">",
                1,
            )

            # game-container 닫기 — <script src="index.js"> 바로 앞
            js_marker = '<script src="index.js">'
            if js_marker in html:
                html = html.replace(
                    js_marker,
                    f'</div><!-- /game-container -->\n\n\t\t<script src="index.js">',
                    1,
                )

    # (5) SEO 메타 태그
    if '<meta name="description"' not in html:
        html = html.replace("</title>", f"</title>\n\t\t{SEO_META}", 1)

    OUTPUT_HTML.write_text(html, encoding="utf-8")
    delta = len(html) - original_len
    print(f"  AdSense 삽입 완료! (+{delta} bytes)")


# ═══════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════

def parse_args():
    """간단한 인자 파싱."""
    ads_only = "--ads-only" in sys.argv
    godot_path = None
    for i, arg in enumerate(sys.argv):
        if arg == "--godot" and i + 1 < len(sys.argv):
            godot_path = sys.argv[i + 1]
    return ads_only, godot_path


def main():
    ads_only, godot_path = parse_args()

    print()
    print("  ╔══════════════════════════════════╗")
    print("  ║   The Yut — Build & Deploy       ║")
    print("  ╚══════════════════════════════════╝")
    print()

    if ads_only:
        print("[1/1] AdSense 삽입")
        inject_adsense()
    else:
        # Step 1: Godot Export
        print("[1/2] Godot Web 내보내기")
        godot_cmd = find_godot(godot_path)
        if not godot_cmd:
            print("  ERROR: Godot를 찾을 수 없습니다.")
            print()
            print("  해결 방법:")
            print("    1) Godot를 PATH에 추가")
            print("    2) python build.py --godot \"C:/path/to/Godot.exe\"")
            print("    3) python build.py --ads-only  (직접 빌드 후 AdSense만 삽입)")
            sys.exit(1)
        run_godot_export(godot_cmd)
        print()

        # Step 2: AdSense
        print("[2/2] AdSense 삽입")
        inject_adsense()

    print()
    print(f"  완료! → {OUTPUT_HTML.relative_to(ROOT)}")
    print()


if __name__ == "__main__":
    main()
