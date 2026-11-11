#!/usr/bin/env bash
# Upload the Facefish mini site to an FTP server using curl.
#
# Configure via environment variables or a git-ignored .env.deploy file next to this script:
#   FTP_HOST=ftp.example.com
#   FTP_USER=username
#   FTP_PASS=password
#   FTP_DIR=/public_html/facefish   # remote target directory (default: /)
#   FTP_TLS=1                       # 1 = explicit FTPS (default), 0 = plain FTP
#
# Usage: ./deploy.sh [--dry-run]
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env.deploy ] && set -a && . ./.env.deploy && set +a
: "${FTP_HOST:?Set FTP_HOST}" "${FTP_USER:?Set FTP_USER}" "${FTP_PASS:?Set FTP_PASS}"
FTP_DIR="/${FTP_DIR#/}"; FTP_DIR="${FTP_DIR%/}"
FTP_TLS="${FTP_TLS:-1}"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

tls=(); [ "$FTP_TLS" = "1" ] && tls=(--ssl-reqd)

# Files to publish (deploy tooling and secrets are excluded)
files=$(find . -type f \( -name '*.html' -o -name '*.css' -o -path './img/*' \) ! -name '.*' | sed 's|^\./||' | sort)

echo "Deploying to ftp://$FTP_HOST$FTP_DIR/ ($(echo "$files" | wc -l | tr -d ' ') files)"
while IFS= read -r f; do
  if [ "$DRY" = 1 ]; then echo "would upload $f"; continue; fi
  echo "uploading $f"
  # Credentials go through a curl config on stdin so they never appear in the process list
  printf 'user = "%s:%s"\n' "$FTP_USER" "$FTP_PASS" | \
    curl -sS --fail --config - ${tls[@]+"${tls[@]}"} --ftp-create-dirs -T "$f" "ftp://$FTP_HOST$FTP_DIR/$f"
done <<< "$files"
echo "Done."
