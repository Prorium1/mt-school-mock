#!/usr/bin/env bash
#
# Prorium AI 開発環境のPortableセットアップ（Mac / Linux / Claude Code Cloud 共通）
#
# 目的:
#   どの環境からこのリポジトリを開いても、同じSkillセット・同じ品質基準で開発できる状態にする。
#
# 使い方:
#   bash .claude/bootstrap.sh          … 不足しているものだけ入れる
#   bash .claude/bootstrap.sh --check  … 何も入れずに現状だけ表示する
#   bash .claude/bootstrap.sh --force  … 導入済み記録を無視して入れ直す
#
# 設計:
#   - 冪等（idempotent）。何度実行しても壊れない。導入済みは飛ばす
#   - 1つ失敗しても止まらず、最後にまとめて結果を出す（Cloudは環境差があるため）
#   - 秘密情報は一切扱わない。APIキー・トークンの入力を求めないし、書き出しもしない
#
# 入れるもの（すべて ~/.claude/skills 配下＝ユーザ全体。リポジトリには入らない）:
#   1. gstack                             … 55 skills（/office-hours /autoplan /review /ship 等）
#   2. ui-ux-pro-max                      … UI/UX設計の知識
#   3. supabase agent-skills              … Supabase運用（postgres-best-practices を含む）
#   4. vercel web-design-guidelines       … Web UIの実装ガイドライン
#
# 参照:
#   gstack                  https://github.com/garrytan/gstack
#   ui-ux-pro-max           https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
#   supabase/agent-skills   https://github.com/supabase/agent-skills
#   vercel-labs/skills      https://github.com/vercel-labs/skills

set -uo pipefail   # -e は使わない。1つ失敗しても残りを試して最後に報告するため

SKILLS_DIR="${HOME}/.claude/skills"
# 導入記録はユーザ側に置く。リポジトリ内に置くと、
#   1. 通常のセットアップだけで作業ツリーが汚れる（未追跡ファイルが増える）
#   2. 記録は ~/.claude/skills の状態を指すのに、HOMEが変わっても記録だけ残る
# の2つが起きる。記録と対象を同じ場所で持たせる（2026-08-28のCodex指摘）
LOCK_FILE="${HOME}/.claude/skills.lock"
# 旧版はリポジトリ内に置いていた。残っていれば読み取りだけ引き継ぐ（削除はしない）
LEGACY_LOCK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills.lock"
MODE="install"

case "${1:-}" in
  --check) MODE="check" ;;
  --force) MODE="force" ;;
  "") ;;
  *) echo "不明な引数: $1（使えるのは --check / --force）"; exit 2 ;;
esac

OK=(); SKIPPED=(); FAILED=()

say()  { printf '%s\n' "$*"; }
head2(){ printf '\n▶ %s\n' "$*"; }

# 導入済み記録。パスの存在確認と併用し、記録だけ残って実体が無い状態を検出する
recorded() {
  [ -f "${LOCK_FILE}" ] && grep -qxF "$1" "${LOCK_FILE}" 2>/dev/null && return 0
  [ -f "${LEGACY_LOCK}" ] && grep -qxF "$1" "${LEGACY_LOCK}" 2>/dev/null
}
# --check は「現状を見るだけ」。記録を書くと、状態を見ただけで環境が変わってしまう
record()   {
  [ "${MODE}" = "check" ] && return 0
  mkdir -p "$(dirname "${LOCK_FILE}")"; recorded "$1" || printf '%s\n' "$1" >> "${LOCK_FILE}"
}

# $1=表示名 $2=実体の判定パス（空なら記録のみで判定） $3...=導入コマンド
ensure() {
  local name="$1" probe="$2"; shift 2
  local installed=0
  if [ -n "${probe}" ] && [ -e "${probe}" ]; then installed=1
  elif [ -z "${probe}" ] && recorded "${name}"; then installed=1
  fi

  if [ "${installed}" = "1" ] && [ "${MODE}" != "force" ]; then
    SKIPPED+=("${name}"); say "  ✓ ${name} … 導入済み"; record "${name}"; return 0
  fi
  if [ "${MODE}" = "check" ]; then
    FAILED+=("${name}（未導入）"); say "  ✗ ${name} … 未導入"; return 0
  fi

  say "  ↓ ${name} を導入します…"
  if "$@" >/dev/null 2>&1; then
    OK+=("${name}"); record "${name}"; say "  ✓ ${name} … 完了"
  else
    FAILED+=("${name}"); say "  ✗ ${name} … 失敗（下に対処を出します）"
  fi
}

say "════════════════════════════════════════════════════"
say " Prorium AI 開発環境セットアップ"
say " モード: ${MODE} / 導入先: ${SKILLS_DIR}"
say "════════════════════════════════════════════════════"

# ── 1. 必要なコマンドの確認 ───────────────────────────────
head2 "必要なコマンドを確認します"
MISSING_CORE=()
for cmd in git curl; do
  if command -v "${cmd}" >/dev/null 2>&1; then say "  ✓ ${cmd}"; else say "  ✗ ${cmd}"; MISSING_CORE+=("${cmd}"); fi
done
if [ "${#MISSING_CORE[@]}" -gt 0 ]; then
  say ""
  say "✋ ${MISSING_CORE[*]} がありません。これが無いと何も進められません。"
  say "   Mac  : xcode-select --install"
  say "   Linux: sudo apt-get install -y ${MISSING_CORE[*]}"
  exit 1
fi
if command -v node >/dev/null 2>&1; then say "  ✓ node ($(node -v))"; else say "  ✗ node（npx を使う導入がすべて飛ばされます）"; fi

# ── 2. Bun（gstack の setup が必要とする）────────────────
head2 "Bun を確認します"
if command -v bun >/dev/null 2>&1; then
  say "  ✓ bun ($(bun --version))"
elif [ -x "${HOME}/.bun/bin/bun" ]; then
  export PATH="${HOME}/.bun/bin:${PATH}"
  say "  ✓ bun（~/.bun/bin にありました。今回の実行だけPATHに追加します）"
elif [ "${MODE}" = "check" ]; then
  say "  ✗ bun … 未導入"
else
  say "  ↓ bun を導入します（公式インストーラ: https://bun.sh/install）…"
  if curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1; then
    export PATH="${HOME}/.bun/bin:${PATH}"
    command -v bun >/dev/null 2>&1 && say "  ✓ bun … 完了" || { say "  ✗ bun … 導入後も見つかりません"; FAILED+=("bun"); }
  else
    say "  ✗ bun … 失敗"; FAILED+=("bun")
  fi
fi

# ── 3. gstack ───────────────────────────────────────────
head2 "gstack"
# gstack の setup は「Skillのリンク」と「ブラウザ（Playwright Chromium）の用意」を両方やる。
# ブラウザの取得だけが失敗する環境（Claude Code Cloud は cdn.playwright.dev を遮断）でも、
# Skill のリンク自体は bin/gstack-relink で完了できる。
# したがって失敗＝全滅とはせず、core / browser を分けて判定する。
GSTACK_DIR="${SKILLS_DIR}/gstack"
GSTACK_LOG="$(mktemp -t gstack-setup.XXXXXX)"
GSTACK_CORE="unknown"      # ok | ng
GSTACK_BROWSER="unknown"   # ok | ng

# core が使えるか＝gstack配下ではなく ~/.claude/skills 直下に Skill がリンクされているか。
# ブラウザ不要の代表2つで見る（どちらも SKILL.md 内に browse への参照が無いことを確認済み）
gstack_core_linked() {
  [ -e "${SKILLS_DIR}/review/SKILL.md" ] && [ -e "${SKILLS_DIR}/investigate/SKILL.md" ]
}

gstack_fetch() {
  mkdir -p "${SKILLS_DIR}" || return 1
  if [ -d "${GSTACK_DIR}/.git" ]; then
    git -C "${GSTACK_DIR}" pull --ff-only || return 1
  else
    rm -rf "${GSTACK_DIR}"
    git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git "${GSTACK_DIR}" || return 1
  fi
}

if [ "${MODE}" = "check" ]; then
  if gstack_core_linked; then
    GSTACK_CORE="ok"; say "  ✓ gstack core … 利用可能"
  else
    # 未導入は「未完了」に数える。数えないと、他が揃っているだけで
    # 「すべて導入済み」と言って終了コード0を返してしまう
    GSTACK_CORE="ng"; FAILED+=("gstack-core（未導入）"); say "  ✗ gstack core … 未導入"
  fi
  if [ -x "${GSTACK_DIR}/browse/dist/browse" ] && [ -d "${GSTACK_DIR}/browse/dist" ]; then
    # 実体があるうえで前回の導入が成功していれば、その記録を信じる。
    # 記録が無いときは「不明」のままにする——**「不明」を「利用不可」に丸めない**。
    # 丸めると、Chromiumが動くMacでもCLAUDE.mdのルールがブラウザ系Skillを止めてしまう
    if recorded "gstack-browser"; then
      GSTACK_BROWSER="ok"; say "  ✓ gstack browser … 利用可能（前回の導入記録）"
    else
      GSTACK_BROWSER="unknown"; say "  ? gstack browser … 判定不能（Chromium起動が要る。bootstrap実行で判定します）"
    fi
  else
    GSTACK_BROWSER="ng"; say "  ✗ gstack browser … 未導入"
  fi
elif gstack_core_linked && [ "${MODE}" != "force" ]; then
  GSTACK_CORE="ok"
  say "  ✓ gstack core … 導入済み"
  SKIPPED+=("gstack-core")
  # ブラウザの状態は記録と実体の両方で判断する。記録だけを信じると、
  # Chromiumが消えていても「利用可能」と言ってしまう
  if recorded "gstack-browser" && [ -x "${GSTACK_DIR}/browse/dist/browse" ]; then
    GSTACK_BROWSER="ok"
  else
    GSTACK_BROWSER="ng"
    # core があると gstack setup ごと飛ばすので、ここを黙ると
    # 「不足を入れる」はずの既定動作でブラウザだけ永久に入らない
    say "  ! gstack browser … 未導入のまま。取り直すには --force を付けて実行"
  fi
else
  say "  ↓ gstack を取得します…"
  if ! gstack_fetch >/dev/null 2>&1; then
    GSTACK_CORE="ng"; GSTACK_BROWSER="ng"
    FAILED+=("gstack（取得に失敗）")
    say "  ✗ gstack … 取得に失敗しました"
  else
    say "  ↓ gstack setup を実行します（数分かかることがあります）…"
    if ( cd "${GSTACK_DIR}" && ./setup ) > "${GSTACK_LOG}" 2>&1; then
      GSTACK_CORE="ok"; GSTACK_BROWSER="ok"
      OK+=("gstack-core" "gstack-browser"); record "gstack-core"; record "gstack-browser"
      say "  ✓ gstack core … 完了"
      say "  ✓ gstack browser … 完了"
    else
      # setup が途中で止まった。ブラウザ取得の遮断が原因かを確かめる。
      # CORE ONLY を「正常な状態」として通してよいのは、**原因がブラウザ取得だと確認できたときだけ**。
      # 依存関係やビルドの失敗まで CORE ONLY に丸めると、setup が完走していないのに
      # 終了コード0で「使える環境」と報告してしまう（2026-08-28のCodex指摘）
      SETUP_FAILURE_EXPLAINED=0
      if grep -qE "cdn\.playwright\.dev|request blocked|Failed to install browsers" "${GSTACK_LOG}" 2>/dev/null; then
        SETUP_FAILURE_EXPLAINED=1
        say "  ! gstack browser … ブラウザの取得を環境に遮断されました"
      else
        say "  ! gstack setup が完了しませんでした（ブラウザ以外の原因です）"
        say "    ログ: ${GSTACK_LOG}"
        FAILED+=("gstack-setup（ブラウザ以外の原因で未完了）")
      fi
      GSTACK_BROWSER="ng"

      # ブラウザ抜きでSkillだけリンクし直す。実体があり実行できるときだけ触る
      if [ -x "${GSTACK_DIR}/bin/gstack-relink" ]; then
        say "  ↓ ブラウザ非依存のSkillをリンクします（bin/gstack-relink）…"
        if ( cd "${GSTACK_DIR}" && ./bin/gstack-relink ) >>"${GSTACK_LOG}" 2>&1 && gstack_core_linked; then
          GSTACK_CORE="ok"
          OK+=("gstack-core")
          record "gstack-core"
          if [ "${SETUP_FAILURE_EXPLAINED}" = "1" ]; then
            say "  ✓ gstack core … 完了（browser を除く）"
          else
            # core は使えるが、setup が完走していない事実は消さない
            say "  △ gstack core … リンクはできたが、setup は完走していない"
          fi
        else
          GSTACK_CORE="ng"
          FAILED+=("gstack-core")
          say "  ✗ gstack core … リンクできませんでした"
        fi
      else
        GSTACK_CORE="ng"
        FAILED+=("gstack-core")
        say "  ✗ gstack core … bin/gstack-relink が見つからず、復旧できません"
      fi
    fi
  fi
fi

# ── 4〜7. npx skills / npx 経由で入るもの ────────────────
# -g=ユーザ全体 / -a claude-code=対象エージェント / -y=確認を出さない（非対話）
if command -v npx >/dev/null 2>&1; then
  head2 "ui-ux-pro-max"
  # -g を付けないとリポジトリ側の .claude/skills へ 4.7MB・172ファイルが入ってしまう。
  # Skillはユーザ全体の持ち物なので ~/.claude/skills に置き、リポジトリには入れない
  ensure "ui-ux-pro-max" "${SKILLS_DIR}/ui-ux-pro-max" \
    npx -y ui-ux-pro-max-cli init --ai claude --global

  head2 "Supabase Agent Skills"
  ensure "supabase-agent-skills" "${SKILLS_DIR}/supabase" \
    npx -y skills add supabase/agent-skills --skill '*' -g -a claude-code -y

  head2 "supabase-postgres-best-practices"
  ensure "supabase-postgres-best-practices" "${SKILLS_DIR}/supabase-postgres-best-practices" \
    npx -y skills add supabase/agent-skills --skill supabase-postgres-best-practices -g -a claude-code -y

  head2 "web-design-guidelines（Vercel）"
  ensure "web-design-guidelines" "${SKILLS_DIR}/web-design-guidelines" \
    npx -y skills add vercel-labs/agent-skills --skill web-design-guidelines -g -a claude-code -y
else
  say ""
  say "✋ npx が無いため、Skill 4種を飛ばしました。Node.js を入れてから再実行してください。"
  FAILED+=("ui-ux-pro-max" "supabase-agent-skills" "supabase-postgres-best-practices" "web-design-guidelines")
fi

# ── 8. 必要なディレクトリ ────────────────────────────────
head2 "ディレクトリを用意します"
mkdir -p "${SKILLS_DIR}" "${HOME}/.claude/plugins" && say "  ✓ ${SKILLS_DIR} / ~/.claude/plugins"

# ── 結果 ────────────────────────────────────────────────
say ""
say "════════════════════════════════════════════════════"
say " 結果"
say "════════════════════════════════════════════════════"
case "${GSTACK_CORE}/${GSTACK_BROWSER}" in
  ok/ok)      say "  gstack core:    利用可能"
              say "  gstack browser: 利用可能" ;;
  # 「判定不能」は「利用不可」と別物として出す。同じにすると、
  # Chromiumが動く環境でもブラウザ系Skillを禁止する判断に倒れる
  ok/unknown) say "  gstack core:    利用可能"
              say "  gstack browser: 判定不能（bootstrap を実行すると判定します）" ;;
  ok/*)       say "  gstack core:    利用可能"
              say "  gstack browser: 利用不可（CORE ONLY／機能を絞って動作します）" ;;
  *)          say "  gstack core:    利用不可"
              say "  gstack browser: 利用不可" ;;
esac
say ""
[ "${#OK[@]}"      -gt 0 ] && say "  導入した:   ${OK[*]}"
[ "${#SKIPPED[@]}" -gt 0 ] && say "  導入済み:   ${SKIPPED[*]}"
[ "${#FAILED[@]}"  -gt 0 ] && say "  未完了:     ${FAILED[*]}"
[ "${#OK[@]}" -eq 0 ] && [ "${#FAILED[@]}" -eq 0 ] && say "  すべて導入済みです。何もしていません。"

# CORE ONLY は「壊れている」ではなく「機能が絞られた正常な状態」として扱う。
# ブラウザが無いことだけを理由に導入失敗と判定しない。
if [ "${GSTACK_CORE}" = "ok" ] && [ "${GSTACK_BROWSER}" != "ok" ] && [ "${MODE}" != "check" ]; then
  say ""
  say "── gstack は CORE ONLY で動作します ──"
  say "  この環境ではブラウザ（Playwright Chromium）を取得できないため、"
  say "  ブラウザを使うSkillだけが使えません。それ以外は通常どおり使えます。"
  say ""
  say "  使える    : /review /investigate /cso /guard /autoplan /plan-ceo-review"
  say "              /plan-eng-review /plan-devex-review /devex-review /spec /health"
  say "              /retro /learn /freeze /unfreeze /careful /context-save /context-restore"
  say "              /document-generate /document-release /ship"
  say "  一部制限  : /office-hours（対話は可。第三者サイトの代行操作のみ不可）"
  say "              /land-and-deploy（デプロイは可。公開後のスモーク確認のみ不可）"
  say "  使えない  : /qa /qa-only /design-review /design-shotgun /design-consultation"
  say "              /design-html /plan-design-review /scrape /benchmark /canary"
  say "              /skillify /open-gstack-browser /pair-agent /setup-browser-cookies"
  say ""
  say "  ブラウザQAは Mac など Chromium が使える環境で行ってください。"
  say "  Cloudでも使いたい場合は、環境のネットワークポリシーで cdn.playwright.dev を"
  say "  許可します（既定では許可しない方針）:"
  say "    https://code.claude.com/docs/en/claude-code-on-the-web"
fi

if [ "${#FAILED[@]}" -gt 0 ] && [ "${MODE}" != "check" ]; then
  say ""
  say "── 未完了があったときの対処 ──"
  say "  1. もう一度実行する（通信の一時的な失敗はこれで直ることが多い）"
  say "       bash .claude/bootstrap.sh"
  say "  2. 原因を見る（このスクリプトは出力を隠すので、直接叩いて確かめる）"
  say "       npx -y skills add supabase/agent-skills --skill '*' -g -a claude-code -y"
  say "  3. gstack core が利用不可のときは bun を確認する"
  say "       bun --version    （無ければ curl -fsSL https://bun.sh/install | bash）"
  say "  4. それでも直らなければ、上の『未完了』の行をそのままClaudeに貼る"
  exit 1
fi

say ""
if [ "${MODE}" = "check" ]; then
  if [ "${#FAILED[@]}" -gt 0 ]; then
    say "未導入のものがあります。入れるには引数なしで実行してください:"
    say "    bash .claude/bootstrap.sh"
    exit 1
  fi
  say "✅ すべて導入済みです。"
  exit 0
fi

say "✅ 完了。Claude Code を開き直すと Skill が読み込まれます。"
say "   確認: /office-hours と打って質問が返ってくれば gstack は有効です。"
