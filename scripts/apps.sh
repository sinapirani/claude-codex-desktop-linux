# Per-app constants shared by the scripts in this repo. Source it, then:
#   app_load NAME     NAME: claude-desktop (alias claude) or chatgpt (alias codex)
# Sets:
#   APP      package name (as in the vendor's .deb and in every recipe)
#   TITLE    human-readable name
#   APT_URL  vendor's apt repository (suite "stable", component "main")
#   KEYRING  armored signing key of that repository, relative to the repo root
# shellcheck shell=bash

APPS="claude-desktop chatgpt"

app_load() {
  case "${1:-}" in
    claude|claude-desktop)
      APP=claude-desktop
      TITLE="Claude Desktop"
      APT_URL=https://downloads.claude.ai/claude-desktop/apt/stable
      KEYRING=keys/claude-desktop-archive-keyring.asc
      ;;
    codex|chatgpt)
      APP=chatgpt
      TITLE="Codex (ChatGPT desktop app)"
      APT_URL=https://persistent.oaistatic.com/codex-app-prod/linux/deb
      KEYRING=keys/chatgpt-archive-keyring.asc
      ;;
    *)
      echo "unknown app '${1:-}': use claude-desktop (claude) or chatgpt (codex)" >&2
      return 1
      ;;
  esac
}
