# 街ごとの両替の手引きを作る:  python tools/city-guides/make.py
# 中身は cities.py。ここは見た目（HTML の型）だけ。出力は guide/<id>-exchange/index.html。
# 手で HTML を直さず、cities.py を直してから走らせ直すこと。
import html, json, pathlib, sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cities import CITIES

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = "https://primarydice.github.io"
PUBLISHED = "2026-10-15"
e = html.escape


def para(s):
    # 文の中の <strong> と <br> だけは HTML として通す（cities.py は自分で書いた文だけ）
    return s


def section(label, body):
    return f"""
  <hr class="incise">

  <section class="section">
    <div class="wrap spec reveal">
      <h2 class="spec-label">{label}</h2>
      <div class="spec-body">
{body}
      </div>
    </div>
  </section>
"""


def fig(src, alt, w, h):
    return f'        <figure class="guide-fig"><img src="/assets/guide/city/{src}" alt="{e(alt)}" width="{w}" height="{h}" loading="lazy" decoding="async"></figure>\n'


def page(c):
    url = f"{BASE}/guide/{c['id']}-exchange/"
    iso = c["updated"].replace(".", "-")
    ld = {
        "@context": "https://schema.org", "@type": "Article",
        "headline": c["title"], "description": c["desc"], "url": url,
        "datePublished": PUBLISHED, "dateModified": iso, "inLanguage": "ja",
        "image": f"{BASE}/assets/guide/city/{c['photo'][0]}",
        "author": {"@type": "Organization", "name": "Primary Dice"},
        "publisher": {"@type": "Organization", "name": "Primary Dice"},
    }

    # 結論
    b = fig(c["photo"][0], c["photo"][1], 1080, 675)
    b += '        <div class="features features--stack" style="margin-top:22px">\n'
    for h, t in c["answer"]:
        b += f"          <div>\n            <h3>{e(h)}</h3>\n            <p>{para(t)}</p>\n          </div>\n"
    b += "        </div>\n"
    b += ('        <div class="note" style="margin-top:22px">\n'
          '          <p class="small">この記事の数字は、それぞれ調べた日の時点のものです。お店・営業時間・決まり・レートは変わります。出発前に、現地の掲示やアプリで最新を確かめてください。内容は3か月ごとに見直しています。</p>\n'
          "        </div>\n")
    out = section("結論", b)

    # 空港
    b = '        <div class="features features--stack" style="margin-top:0">\n'
    for a in c["airports"]:
        if a["photo"]:
            b += fig(a["photo"][0], a["photo"][1], 960, 480).replace("        <figure", "          <figure")
        b += f"          <div>\n            <h3>{e(a['name'])}：{e(a['head'])}</h3>\n"
        for i, p in enumerate(a["ps"]):
            sp = ' style="margin-top:12px"' if i else ""
            b += f"            <p{sp}>{para(p)}</p>\n"
        b += "          </div>\n"
    b += "        </div>\n"
    out += section("空港で", b)

    # 街で
    b = '        <div class="features features--stack" style="margin-top:0">\n'
    for h, t in c["city"]:
        b += f"          <div>\n            <h3>{e(h)}</h3>\n            <p>{para(t)}</p>\n          </div>\n"
    b += "        </div>\n"
    out += section("街で", b)

    # 気をつけること
    b = '        <ul class="list" style="max-width:38em">\n' + "".join(f"          <li>{para(t)}</li>\n" for t in c["cautions"]) + "        </ul>\n"
    out += section("気をつけること", b)

    # 実例
    x = c["example"]
    b = ('        <p style="max-width:38em">どのくらい変わるのか、調べた日の数字を挙げます。その日の時点のもので、今の数字ではありません。</p>\n'
         '        <div class="features features--stack" style="margin-top:22px">\n'
         f"          <div>\n            <h3>{e(x['title'])}</h3>\n            <p>{para(x['text'])}</p>\n"
         f'            <p class="small"><a class="link-block" href="{e(x["src"][1])}" rel="noopener">出典：{e(x["src"][0])}</a></p>\n'
         "          </div>\n        </div>\n")
    out += section("実例", b)

    # アプリ・ほかの街
    others = "　".join(f'<a class="link-block" href="/guide/{o["id"]}-exchange/">{e(o["name"])}</a>' for o in CITIES if o["id"] != c["id"])
    b = (f'        <p style="max-width:38em">この記事は要点だけをまとめたものです。{e(c["name"])}の両替所の場所と営業時間、空港に着いてからの順路、地図、街ごとの気をつけることは、Android アプリ「<a class="link-block" href="/ratehunt/">レートハント</a>」に入れています。電波のない場所でも使えます。</p>\n'
         '        <p style="margin-top:22px"><a class="gp-badge gp-badge--lg" href="https://play.google.com/store/apps/details?id=app.primarydice.ratehunt" rel="noopener"><img src="/assets/google-play-badge.svg" alt="レートハントを Google Play で手に入れよう" width="180" height="53"></a></p>\n'
         '        <p class="tm">Google Play および Google Play ロゴは Google LLC の商標です。</p>\n'
         f'        <p class="small" style="margin-top:22px">ほかの街：{others}</p>\n'
         '        <p class="small" style="margin-top:12px"><a class="link-block" href="/guide/airport-exchange/">あわせて読む：空港に着いてからの両替（アジア8都市の動き方）</a></p>\n'
         '        <p class="small" style="margin-top:6px"><a class="link-block" href="/guide/city-exchange/">あわせて読む：街なかで両替するときの落とし穴（アジア5か国の決まりの違い）</a></p>\n')
    out += section("アプリ", b)

    short_title = c["title"]
    return f"""<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(short_title)} | Primary Dice</title>
<meta name="description" content="{e(c['desc'])}">
<meta name="theme-color" content="#070b14">
<link rel="canonical" href="{url}">

<meta property="og:type" content="article">
<meta property="og:site_name" content="Primary Dice">
<meta property="og:title" content="{e(short_title)}">
<meta property="og:description" content="{e(c['desc'])}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{BASE}/assets/guide/city/{c['photo'][0]}">
<meta name="twitter:card" content="summary_large_image">

<link rel="icon" href="/assets/favicon.png" type="image/png" sizes="512x512">
<link rel="apple-touch-icon" href="/assets/favicon.png">
<link rel="stylesheet" href="/assets/style.css">

<script>
if (window.matchMedia && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {{
  document.documentElement.className += ' js-reveal';
}}
</script>

<script type="application/ld+json">
{json.dumps(ld, ensure_ascii=False, indent=2)}
</script>
</head>
<body>

<a class="skip-link" href="#main">本文へスキップ</a>

<header class="site-header">
  <div class="wrap">
    <a class="home" href="/"><img src="/assets/logo.png" alt="Primary Dice" width="879" height="200"></a>
    <nav class="site-nav" aria-label="サイト内">
      <a href="/#products">Products</a>
      <a href="/#labs">Labs</a>
      <a href="/#company">Company</a>
    </nav>
  </div>
</header>

<main id="main">

  <section class="page-head">
    <div class="wrap">
      <h1 class="polish">{e(c['name'])}の両替</h1>
      <p class="hero-note" style="margin-top:12px">
        {c['lead']}
      </p>
      <p class="small dim data" style="margin-top:10px">{e(c['country'])}　最終更新　{c['updated']}</p>
    </div>
  </section>
{out}
</main>

<footer class="site-footer">
  <div class="wrap">
    <span class="copy">© 2026 Primary Dice</span>
    <span><a href="/privacy/">プライバシーポリシー</a></span>
  </div>
</footer>

<script src="/assets/site.js" defer></script>
</body>
</html>
"""


for c in CITIES:
    d = ROOT / "guide" / f"{c['id']}-exchange"
    d.mkdir(parents=True, exist_ok=True)
    s = page(c)
    (d / "index.html").write_text(s, encoding="utf-8", newline="\n")
    body = s[s.index("<main"):s.index("</main>")]
    import re
    text = re.sub(r"<[^>]+>", "", body)
    print(c["id"], len(re.sub(r"\s+", "", text)), "字")
