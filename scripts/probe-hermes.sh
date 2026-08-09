#!/usr/bin/env bash
#
# probe-hermes.sh — discover what a Hermes host actually serves.
#
# Runs the same requests the iOS app makes (/health and /v1/models) and reports the
# HTTP status, Content-Type, any redirect, and a short body preview so you can tell
# whether you are reaching the OpenAI-compatible API server (JSON) or the web
# dashboard / a proxy landing page (HTML).
#
# Usage:
#   scripts/probe-hermes.sh --url https://hermes.example.ts.net:8443 [auth]
#
# Auth options (pick the one that matches how you log in):
#   --key   YOUR_API_SERVER_KEY        # Bearer token (what the API server wants)
#   --user  USERNAME --pass PASSWORD   # HTTP Basic (dashboard / proxy edge)
#   (none)                             # no auth, to see the raw response
#
# In the reference Azure deployment the Tailscale Service publishes the dashboard
# on :443 and the API server on :8443. Probe :8443 with --key.
#
# Examples:
#   scripts/probe-hermes.sh --url https://hermes.example.ts.net:8443 --key sk-...
#   scripts/probe-hermes.sh --url https://hermes.example.ts.net --user mike --pass 'secret'
#
# Nothing is stored or transmitted anywhere except to the host you specify.

set -uo pipefail

URL=""
USER=""
PASS=""
KEY=""

die() { printf 'error: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --url)  URL="${2:-}"; shift 2 ;;
    --user) USER="${2:-}"; shift 2 ;;
    --pass) PASS="${2:-}"; shift 2 ;;
    --key)  KEY="${2:-}"; shift 2 ;;
    -h|--help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$URL" ] || die "missing --url"
URL="${URL%/}"

AUTH=()
AUTH_LABEL="none"
if [ -n "$KEY" ]; then
  AUTH=(-H "Authorization: Bearer $KEY")
  AUTH_LABEL="Bearer API key"
elif [ -n "$USER" ]; then
  AUTH=(--user "$USER:$PASS")
  AUTH_LABEL="Basic (username/password)"
fi

host_only="${URL#*://}"
host_only="${host_only%%/*}"

printf 'Probing %s\n' "$URL"
printf 'Auth:   %s\n' "$AUTH_LABEL"
printf 'Host:   %s\n\n' "$host_only"

probe() {
  local label="$1" path="$2"
  local full="$URL$path"
  local body meta code ctype eurl preview
  body="$(mktemp)"
  # Fields are '|'-separated. '|' is not IFS-whitespace, so empty fields (e.g. a 302
  # with no Content-Type) are preserved instead of being collapsed into the next field.
  meta="$(curl -sS -m 15 -o "$body" \
    -w '%{http_code}|%{content_type}|%{redirect_url}|%{url_effective}' \
    ${AUTH[@]+"${AUTH[@]}"} -H 'Accept: application/json' "$full" 2>/dev/null || printf '000|||%s' "$full")"
  IFS='|' read -r code ctype redirect eurl <<<"$meta"
  preview="$(head -c 240 "$body" | tr '\n\r\t' '   ' | sed 's/  */ /g' | sed 's/^ //')"
  rm -f "$body"

  printf '%s  %s\n' "$label" "$full"
  printf '   status : %s\n' "${code:-?}"
  printf '   type   : %s\n' "${ctype:-none}"
  if [ -n "$redirect" ]; then
    printf '   redirect -> %s\n' "$redirect"
  fi
  printf '   body   : %s\n\n' "${preview:-(empty)}"

  LAST_CODE="$code"
  LAST_TYPE="$ctype"
  LAST_REDIRECT="$redirect"
}

LAST_CODE=""; LAST_TYPE=""; LAST_REDIRECT=""
probe "[health]     " "/health"
probe "[v1/models]  " "/v1/models"
MODELS_CODE="$LAST_CODE"
MODELS_TYPE="$LAST_TYPE"
MODELS_REDIRECT="$LAST_REDIRECT"

echo "----------------------------------------"
case "$MODELS_CODE" in
  3??)
    echo "VERDICT: /v1/models redirected (HTTP $MODELS_CODE) to:"
    echo "         ${MODELS_REDIRECT:-<no Location header>}"
    echo
    echo "Following the redirect chain to see where it lands..."
    fbody="$(mktemp)"
    fmeta="$(curl -sSL -m 25 --max-redirs 10 -o "$fbody" \
      -w '%{http_code}|%{content_type}|%{url_effective}' \
      ${AUTH[@]+"${AUTH[@]}"} -H 'Accept: application/json' "$URL/v1/models" 2>/dev/null || printf '000||')"
    IFS='|' read -r fcode fctype furl <<<"$fmeta"
    fprev="$(head -c 200 "$fbody" | tr '\n\r\t' '   ' | sed 's/  */ /g' | sed 's/^ //')"
    rm -f "$fbody"
    printf '   final status : %s\n' "${fcode:-?}"
    printf '   final type   : %s\n' "${fctype:-none}"
    printf '   final url    : %s\n' "${furl:-?}"
    printf '   final body   : %s\n\n' "${fprev:-(empty)}"
    case "$furl $fctype" in
      *html*|*login*|*auth*|*oauth*|*sso*)
        echo "This lands on an HTML/login page, so this origin is the web dashboard, not"
        echo "the API server. Redirect-based auth (cookie / SSO / Tailscale identity)"
        echo "cannot be used as an API credential."
        echo
        echo "The OpenAI-compatible API server is a different origin. In the reference"
        echo "Azure deployment the Tailscale Service publishes it on port 8443, so retry"
        echo "with --url https://<same-host>:8443. The API server's own port (8642) is"
        echo "bound to loopback and is not reachable from a client." ;;
      *json*)
        echo "After following redirects it returned JSON. The app also follows same-host"
        echo "HTTPS redirects, so this URL may work once the credential is accepted." ;;
      *)
        echo "Share this final destination and I'll interpret it." ;;
    esac
    ;;
  *)
    case "$MODELS_TYPE" in
      *json*)
        if [ "$MODELS_CODE" = "200" ]; then
          echo "VERDICT: /v1/models returned JSON. This looks like the API server."
          echo "In the app, leave Username blank and put your API key in the API key field,"
          echo "using this exact URL."
        elif [ "$MODELS_CODE" = "401" ] || [ "$MODELS_CODE" = "403" ]; then
          echo "VERDICT: The API server is here but rejected the credential (HTTP $MODELS_CODE)."
          echo "It wants the Bearer API_SERVER_KEY. Re-run with --key YOUR_API_SERVER_KEY."
        else
          echo "VERDICT: JSON came back with HTTP $MODELS_CODE. Share this output."
        fi
        ;;
      *html*)
        echo "VERDICT: /v1/models returned HTML, not JSON."
        echo "You are reaching the web dashboard or a proxy landing page, not the API server."
        echo "Next steps:"
        echo "  1) On the Hermes host, enable the API server and set a key:"
        echo "        hermes config set API_SERVER_ENABLED true"
        echo "        hermes config set API_SERVER_KEY \"\$(openssl rand -hex 32)\""
        echo "        hermes config get API_SERVER_KEY   # copy this into the app"
        echo "  2) Find the API server origin (default port 8642) and make it reachable"
        echo "     over Tailscale, then point the app at that URL."
        echo "  3) In the app: leave Username blank, paste the API key in the API key field."
        ;;
      "")
        echo "VERDICT: No usable response (HTTP ${MODELS_CODE:-000}). Check Tailscale, the host, and the URL."
        ;;
      *)
        echo "VERDICT: /v1/models returned Content-Type '$MODELS_TYPE' (HTTP $MODELS_CODE)."
        echo "Share this output and I'll interpret it."
        ;;
    esac
    ;;
esac
