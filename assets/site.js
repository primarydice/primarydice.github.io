/* =========================================================================
   Primary Dice 公式サイト — 共通スクリプト
   やっていることは2つだけです。
     1. メールアドレスを組み立てて、クリックできるリンクにする
     2. スクロールしたときに、要素をふわっと1回だけ表示する
   どちらも「動かなくても内容は読める」作りにしてあります。
   ========================================================================= */
(function () {
  'use strict';

  /* -----------------------------------------------------------------------
     1. メールアドレス
     HTML には「primarydice-develop［アットマーク］yahoo.co.jp」と書いてあり、
     アットマークの記号そのものは入っていません。
     世の中には、Webページを自動で読み込んでメールアドレスだけを集め、
     迷惑メールを送るためのプログラムがあります。記号を分けておくと、
     その多くに拾われずに済みます(完全には防げません)。
     ページを開いた人には、下の処理で普通のリンクとして表示されます。
     ----------------------------------------------------------------------- */
  var mail = document.getElementById('mail');
  if (mail && mail.getAttribute('data-u') && mail.getAttribute('data-h')) {
    var address = mail.getAttribute('data-u') + '@' + mail.getAttribute('data-h');
    var link = document.createElement('a');
    link.href = 'mailto:' + address;
    link.textContent = address;
    mail.textContent = '';
    mail.appendChild(link);
  }

  /* -----------------------------------------------------------------------
     2. スクロールで1回だけ現れる動き

     「画面に入ったかどうか」を、要素の位置を直接測って判定しています。
     IntersectionObserver という専用の仕組みもありますが、環境によっては
     動かないことがあり、その場合に中身が見えなくなってしまうため、
     確実に動く単純な方法を選んでいます(対象は10個程度なので負荷も問題ありません)。

     ・「視差効果を減らす」設定の人には、何もしません(最初から全部見えています)
     ・一度表示した要素は対象から外すので、繰り返し動くことはありません
     ・このファイル自体が読み込めなかった場合も、CSS 側の安全網で表示されます
     ----------------------------------------------------------------------- */
  var html = document.documentElement;
  if (html.className.indexOf('js-reveal') === -1) { return; }

  var targets = [];
  var nodes = document.querySelectorAll('.reveal');
  for (var i = 0; i < nodes.length; i++) { targets.push(nodes[i]); }
  if (!targets.length) { return; }

  // CSS の安全網(6秒後に自動表示)を止める。ここから先はこのスクリプトが担当する。
  html.className += ' js-reveal-ok';

  function update() {
    var limit = (window.innerHeight || html.clientHeight) * 0.92; // 画面下から8%手前で反応
    for (var i = targets.length - 1; i >= 0; i--) {
      var top = targets[i].getBoundingClientRect().top;
      if (top < limit) {
        targets[i].className += ' is-visible';
        targets.splice(i, 1); // 表示済みは対象から外す
      }
    }
    if (!targets.length) {
      window.removeEventListener('scroll', update);
      window.removeEventListener('resize', update);
    }
  }

  window.addEventListener('scroll', update, { passive: true });
  window.addEventListener('resize', update);
  update();          // 最初から画面に入っている分をすぐ表示
  setTimeout(update, 300); // 画像の読み込みで位置がずれた場合に備えてもう一度
})();
