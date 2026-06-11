#!/usr/bin/env bash

XCODE_AUTH_ARGS=(-allowProvisioningUpdates)

api_key_path="${APP_STORE_CONNECT_API_KEY_PATH:-}"
api_key_id="${APP_STORE_CONNECT_API_KEY_ID:-}"
api_key_issuer_id="${APP_STORE_CONNECT_API_ISSUER_ID:-}"

if [[ -n "$api_key_path" || -n "$api_key_id" || -n "$api_key_issuer_id" ]]; then
  if [[ -z "$api_key_path" || -z "$api_key_id" || -z "$api_key_issuer_id" ]]; then
    echo "App Store Connect API authentication requires key path, key ID, and issuer ID." >&2
    return 1
  fi

  if [[ ! -f "$api_key_path" ]]; then
    echo "App Store Connect API key not found: $api_key_path" >&2
    return 1
  fi

  XCODE_AUTH_ARGS+=(
    -authenticationKeyPath "$api_key_path"
    -authenticationKeyID "$api_key_id"
    -authenticationKeyIssuerID "$api_key_issuer_id"
  )
fi
