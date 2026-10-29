#!/usr/bin/env bash

# Keep source deploy.sh from changing the caller's directory or shell options.
(
  set -e

  if [ -n "${ZSH_VERSION:-}" ]; then
    script_path=${(%):-%x}
  else
    script_path=${BASH_SOURCE[0]}
  fi
  cd -- "$(dirname -- "$script_path")"

  for tool in git gh npm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Required command not found: $tool" >&2
      exit 1
    fi
  done

  # Check the same destination used by gh-pages, without changing accounts.
  remote_url=$(git remote get-url --push origin)
  case "$remote_url" in
    https://github.com/*) deploy_repo=${remote_url#https://github.com/} ;;
    *)
      echo "Expected a GitHub HTTPS origin; found: $remote_url" >&2
      exit 1
      ;;
  esac
  deploy_repo=${deploy_repo%.git}

  if ! active_user=$(gh api --hostname github.com user --jq .login); then
    echo "Log in with: gh auth login --hostname github.com --git-protocol https --web" >&2
    exit 1
  fi
  echo ">>> GitHub account: $active_user; repository: $deploy_repo"

  can_push=$(gh api --hostname github.com "repos/$deploy_repo" --jq '.permissions.push')
  if [ "$can_push" != "true" ]; then
    echo "$active_user does not have write permission to $deploy_repo." >&2
    echo "Ask the repository owner for write access and accept the invitation." >&2
    exit 1
  fi

  # Use gh authentication for Git children, including gh-pages' cached clone.
  # Append process-local settings without changing global Git configuration.
  config_index=${GIT_CONFIG_COUNT:-0}
  export "GIT_CONFIG_KEY_${config_index}=credential.https://github.com.helper"
  export "GIT_CONFIG_VALUE_${config_index}="
  config_index=$((config_index + 1))
  export "GIT_CONFIG_KEY_${config_index}=credential.https://github.com.helper"
  export "GIT_CONFIG_VALUE_${config_index}=!gh auth git-credential"
  export GIT_CONFIG_COUNT=$((config_index + 1))

  echo ">>> clean previous build"
  rm -rf out .next

  echo ">>> build"
  npm run build

  echo ">>> deploy"
  # Build once above; skip the redundant predeploy lifecycle hook.
  npm --ignore-scripts run deploy -- --repo "$remote_url"

  echo ">>> clean successful build"
  rm -rf out .next
)
