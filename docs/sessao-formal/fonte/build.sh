#!/bin/bash
# Builds the formal-session PDFs from the HTML sources in this folder.
#
# The PDFs are what goes to participants and stays with the researcher; the HTML is what gets
# edited. Run this again after changing a text, or to fill in the researcher's contact details,
# which the participant documents carry as {{EMAIL}} and {{TELEFONE}}:
#
#   EMAIL="nome@exemplo.com" TELEFONE="(81) 90000-0000" ./build.sh
#
# Without them the documents show a visible placeholder instead of a contact.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$(dirname "$here")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

email="${EMAIL:-[e-mail do pesquisador]}"
phone="${TELEFONE:-[telefone do pesquisador]}"

swiftc -swift-version 5 -O -o "$work/render-pdf" "$here/render-pdf.swift"
cp "$here/style.css" "$work/"

for source in "$here"/*.html; do
  name="$(basename "$source" .html)"

  sed -e "s|{{EMAIL}}|$email|g" -e "s|{{TELEFONE}}|$phone|g" "$source" > "$work/$name.html"

  if ! "$work/render-pdf" "$work/$name.html" "$out/$name.pdf" 2> "$work/error.log"; then
    cat "$work/error.log" >&2
    echo "failed to render $name" >&2
    exit 1
  fi

  echo "built $name.pdf"
done
