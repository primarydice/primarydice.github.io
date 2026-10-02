// Google Play に出ている各アプリの「最新の版」を読みに行き、
// 新しい版が出ていたら会社サイトを書き換えるスクリプトです。
//
// 動かすのは GitHub Actions(.github/workflows/play-sync.yml)で、1日1回。
// 書き換えた内容はすぐ本番には出さず、「プルリクエスト(変更の下書き)」にして
// 持ち主が中身を見て [Merge] を押したときに本番へ出ます。
//
// 手元で試すとき:  cd tools/play-sync && npm ci && node sync.mjs
//   (書き換えるだけで、git には何もしません)
//
// 書き換えるところ
//   - トップの「記録」に「◯◯を 1.0.3 に更新しました。」を1行足す
//   - アプリのページの <!-- play-sync:start --> 〜 <!-- play-sync:end --> の間
//     (最新版の番号・更新日・この版で変わったこと)
//   - アプリのページの説明データ(JSON-LD)の softwareVersion / dateModified
//   - sitemap.xml の lastmod(トップとそのアプリのページ)
// ストアの画像が変わったときは、サイトの画像は自動では替えず、プルリクエストに書いて知らせます
// (画像ごとの説明文やスマホの枠の有無は、人が決めるため)。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
import gplay from 'google-play-scraper';

const here = path.dirname(fileURLToPath(import.meta.url));
const site = path.resolve(here, '..', '..');
const statePath = path.join(here, 'state.json');
const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));

// 公開してよいメールアドレスはこれだけ(CLAUDE.md 決まり事 8)
const ALLOWED_EMAIL = 'primarydice@gmail.com';

const read = (p) => fs.readFileSync(path.join(site, p), 'utf8');
const write = (p, s) => fs.writeFileSync(path.join(site, p), s);
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// Play の更新日はミリ秒の数字。日本時間の日付にする
const jstDate = (ms) => new Date(ms + 9 * 3600e3).toISOString().slice(0, 10);

// 「新機能」の文を1項目ずつに分ける(<br> 区切り・先頭の「・」を取る)
function splitNotes(text) {
  return (text || '')
    .split(/<br\s*\/?>|\n/i)
    .map((s) => s.replace(/<[^>]+>/g, '').replace(/^[\s・\-*•]+/, '').trim())
    .filter(Boolean);
}

// サイトに載せてはいけない言い回し・メールアドレスが混じっていないか
function checkWords(app, lines) {
  const hits = [];
  for (const line of lines) {
    for (const w of app.ngWords || []) if (line.includes(w)) hits.push(`「${w}」`);
    for (const m of line.match(/[\w.+-]+@[\w-]+\.[\w.-]+/g) || []) {
      if (m !== ALLOWED_EMAIL) hits.push(`メールアドレス ${m}`);
    }
  }
  return hits;
}

const report = [];   // プルリクエストの本文
const warnings = [];
let changed = false;

for (const app of state.apps) {
  let info;
  try {
    info = await gplay.app({ appId: app.appId, lang: 'ja', country: 'jp' });
  } catch (e) {
    warnings.push(`${app.name}: Google Play のページを読めませんでした(${e.message})。次の日にもう一度試します。`);
    continue;
  }

  // ストアの画像が変わったかどうか(画像の住所の一覧で見分ける)
  const shotsHash = crypto.createHash('sha1').update(info.screenshots.join('\n')).digest('hex').slice(0, 12);
  if (app.shotsHash && app.shotsHash !== shotsHash) {
    report.push(`### ${app.name}: ストアの画像が変わりました`,
      'サイトの画像は自動では替えていません。差し替えるときは Claude に「サイトのアプリの写真更新して」と頼んでください。', '');
  }
  if (app.shotsHash !== shotsHash) { app.shotsHash = shotsHash; changed = true; }

  if (info.version === app.version) continue;

  // ---- 新しい版が出ている ----
  const date = jstDate(info.updated);
  const dot = date.replace(/-/g, '.');
  const notes = splitNotes(info.recentChanges);
  const hits = checkWords(app, notes);
  if (hits.length) warnings.push(`${app.name}: 「新機能」の文に、サイトでは使わない言葉があります → ${[...new Set(hits)].join('、')}。Merge の前に直してください。`);

  // 1) トップの「記録」に1行足す(同じ版の行がもうあれば足さない)
  let top = read('index.html');
  const line = `${app.name}を ${info.version} に更新しました。`;
  if (!top.includes(line)) {
    top = top.replace(/(<ul class="log">\r?\n)/,
      `$1          <li><time class="data" datetime="${date}">${dot}</time><span>${esc(line)}</span></li>\n`);
    write('index.html', top);
  }

  // 2) アプリのページの「最新版」の欄
  const pagePath = `${app.slug}/index.html`;
  let page = read(pagePath);
  const block = [
    '<!-- play-sync:start  ここから下は tools/play-sync が自動で書き換えます。手で直すと次の更新で消えます -->',
    '        <div class="note" style="margin-top:18px">',
    `          <p class="small">最新版：<span class="data">${esc(info.version)}</span>（${dot} 更新）</p>`,
    ...notes.map((n) => `          <p class="small">・${esc(n)}</p>`),
    '        </div>',
    '        <!-- play-sync:end -->',
  ].join('\n');
  if (page.includes('<!-- play-sync:start')) {
    page = page.replace(/<!-- play-sync:start[\s\S]*?<!-- play-sync:end -->/, block);
  } else {
    // 初回: 「Google Play で公開しています」の枠のすぐ下に入れる
    const re = /(<p class="small">[^<]*Google Play で公開しています。[^<]*<\/p>\r?\n\s*<\/div>\r?\n)/;
    if (!re.test(page)) { warnings.push(`${app.name}: ページに「Google Play で公開しています」の枠が見つからず、最新版の欄を入れられませんでした。`); }
    page = page.replace(re, `$1        ${block}\n`);
  }

  // 3) 説明データ(検索エンジン向け)に版と更新日
  page = page.replace(/(\n\s*)"softwareVersion": "[^"]*",\n\s*"dateModified": "[^"]*",/, '');
  page = page.replace(/(\n(\s*)"installUrl": "[^"]*",)/,
    `$1\n$2"softwareVersion": "${info.version}",\n$2"dateModified": "${date}",`);
  write(pagePath, page);

  // 4) サイトマップの更新日
  let sm = read('sitemap.xml');
  for (const loc of ['https://primarydice.github.io/', `https://primarydice.github.io/${app.slug}/`]) {
    const re = new RegExp(`(<loc>${loc.replace(/[.\/]/g, '\\$&')}</loc>\\s*<lastmod>)[^<]*`);
    sm = sm.replace(re, (all, head) => {
      const old = all.slice(head.length);
      return head + (old > date ? old : date);
    });
  }
  write('sitemap.xml', sm);

  report.push(`### ${app.name}: ${app.version ?? '(初回)'} → ${info.version}（${dot} 更新）`,
    ...notes.map((n) => `- ${n}`),
    '', `記録に「${line}」を足しました。`, '');
  app.version = info.version;
  changed = true;
}

fs.writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');

const body = [
  'Google Play に新しい版が出ていたので、会社サイトを書き換えた下書きです。',
  '中身を見て、よければ下の **[Merge pull request]** を押してください。1分ほどで本番のサイトに出ます。',
  '記録の文などを直したいときは、Claude に「サイト更新のプルリクエストを直して」と頼んでください。',
  '',
  ...(warnings.length ? ['## ⚠ 注意', ...warnings.map((w) => `- ${w}`), ''] : []),
  ...report,
].join('\n');

const bodyPath = process.env.PR_BODY_FILE || path.join(here, 'pr-body.md');
fs.writeFileSync(bodyPath, body + '\n');
console.log(body);
