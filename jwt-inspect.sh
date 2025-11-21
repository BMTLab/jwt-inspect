#!/bin/bash

# Name: jwt-inspect.sh
# Author: Nikita Neverov (BMTLab)
# Version: 1.0.0
# Date: 2025-11-21
# License: MIT
#
# Description:
#   Decodes and displays JSON Web Tokens (JWT) directly in the terminal.
#   It separates the Header and Payload, pretty-prints the JSON,
#   validates time claims ('exp', 'nbf', 'iat'), and verifies the signature.
#
#   Features:
#     - Safety: Works locally, no data sent to external servers.
#     - Validation: Checks 'exp' claim (time) and Signature (integrity).
#     - Time Claims: Decodes 'iat' (Issued At) and 'nbf' (Not Before).
#     - Compatibility: Supports both GNU date (Linux) and BSD date (macOS).
#     - Security: Supports HS256 signature verification via OpenSSL.
#     - Inputs: Accepts secret via flag -k or JWT_SECRET env var.
#
#   Security Warning:
#     Passing the secret key via the -k flag may cause it to be saved
#     in your shell history file (~/.bash_history).
#     While this tool is safer than pasting tokens into web-based debuggers,
#     consider using the JWT_SECRET environment variable for sensitive keys
#     to avoid history logging.
#
# Usage:
#   jwt_inspect <token>
#   jwt_inspect <token> -k 'my-secret'
#   echo '<token>' | jwt_inspect -k 'secret'
#   export JWT_SECRET='s3cr3t'; jwt_inspect <token>
#
# Dependencies:
#   - jq (highly recommended for JSON formatting and coloring)
#   - base64 (coreutils)
#   - openssl (required for signature verification)
#
# Exit Codes:
#   0: Success.
#   1: JWT_ERR_GENERAL
#      General error.
#   2: JWT_ERR_USAGE
#      Invalid usage or arguments.
#   3: JWT_ERR_INVALID_FORMAT
#      Not a valid JWT structure.
#   4: JWT_ERR_SIG_MISMATCH
#      Signature verification failed.

# Detect whether script is sourced or executed.
# bashsupport disable=BP5001
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
  readonly JWT_SCRIPT_SOURCED=true
else
  readonly JWT_SCRIPT_SOURCED=false
  set -o errexit -o nounset -o pipefail
fi

# Error codes (readonly constants)
if [[ -z ${JWT_ERR_GENERAL+x} ]]; then
  readonly JWT_ERR_GENERAL=1
fi
if [[ -z ${JWT_ERR_USAGE+x} ]]; then
  readonly JWT_ERR_USAGE=2
fi
if [[ -z ${JWT_ERR_INVALID_FORMAT+x} ]]; then
  readonly JWT_ERR_INVALID_FORMAT=3
fi
if [[ -z ${JWT_ERR_SIG_MISMATCH+x} ]]; then
  readonly JWT_ERR_SIG_MISMATCH=4
fi

#######################################
# Print usage information.
#
# Outputs:
#   Usage text to stdout.
#######################################
function __jwt_usage() {
  cat << 'EOF'
jwt_inspect - decode and analyze JSON Web Tokens

Usage:
  jwt_inspect [-k <secret>] <token>
  echo '<token>' | jwt_inspect [-k <secret>]

Description:
  Decodes the Base64Url encoded parts of a JWT (Header and Payload).
  Can optionally verify HS256 signatures if a secret key is provided.

Options:
  -k <secret>  Shared secret key for HMAC signature verification.
               If not provided, checks JWT_SECRET environment variable.
  -h           Show this help message.

Security Warning:
  Passing the secret key via -k may be saved in your shell history.
  While local validation is safer than web services,
  using the JWT_SECRET environment variable is recommended for sensitive keys.
EOF
}

#######################################
# Print error message and exit/return.
#
# Arguments:
#   1: Error message (string).
#   2: Exit code (integer, default: JWT_ERR_GENERAL).
#
# Outputs:
#   Error message to stderr.
#######################################
function __jwt_error() {
  local -r message="$1"
  local -ir code="${2:-$JWT_ERR_GENERAL}"

  printf 'ERROR: %s\n' "$message" >&2

  if [[ $JWT_SCRIPT_SOURCED == true ]]; then
    return "$code"
  else
    exit "$code"
  fi
}

#######################################
# Check if a command exists.
#
# Arguments:
#   1: Command name.
#
# Returns:
#   0: If exists.
#   1: Otherwise.
#######################################
function __jwt_has_cmd() {
  command -v "$1" > /dev/null 2>&1
}

#######################################
# Extract a scalar value from a JSON string.
# Tries to use 'jq' if available, otherwise falls back to grep/cut.
#
# Arguments:
#   1: JSON string.
#   2: Key name to extract.
#
# Outputs:
#   Value of the key (or empty string if not found/null).
#######################################
function __jwt_get_json_value() {
  local -r json_input="$1"
  local -r json_key="$2"
  local extracted_value=''

  if __jwt_has_cmd jq; then
    extracted_value=$(echo "$json_input" | jq -r ".${json_key} // empty")
  else
    # Fallback: simple regex for "key": "value" or "key": 123
    # Warning: This is fragile and only works for simple scalars.
    extracted_value=$(echo "$json_input" \
      | grep -o "\"${json_key}\": *[^,}]*" \
      | cut -d':' -f2- \
      | tr -d ' "')
  fi

  printf '%s' "$extracted_value"
}

#######################################
# Decode Base64Url string to raw text.
#
# Arguments:
#   1: Base64Url string.
#
# Outputs:
#   Decoded string to stdout.
#######################################
function __jwt_decode_part() {
  local input_string="$1"

  # 1. Calculate required padding
  local -ir remainder=$((${#input_string} % 4))
  if [[ $remainder -eq 2 ]]; then
    input_string+='=='
  elif [[ $remainder -eq 3 ]]; then
    input_string+='='
  fi

  # 2. Translate URL-safe chars to standard Base64 and decode
  # Replace '-' with '+' and '_' with '/' using Bash substitution
  input_string="${input_string//-/+}"
  input_string="${input_string//_//}"

  printf '%s' "$input_string" | base64 -d 2> /dev/null
}

#######################################
# Convert Standard Base64 to Base64Url.
#
# Arguments:
#   1: Standard Base64 string.
#
# Outputs:
#   Base64Url string to stdout.
#######################################
function __jwt_to_base64url() {
  local input_string="$1"

  # Translate '+' to '-'
  input_string="${input_string//+/-}"
  # Translate '/' to '_'
  input_string="${input_string//\//_}"
  # Remove padding '='
  input_string="${input_string//=/}"

  printf '%s' "$input_string"
}

#######################################
# Pretty print JSON using jq if available.
#
# Arguments:
#   1: Raw JSON string.
#######################################
function __jwt_format_json() {
  local -r json_input="$1"

  if __jwt_has_cmd jq; then
    echo "$json_input" | jq .
  elif __jwt_has_cmd python3; then
    echo "$json_input" | python3 -m json.tool
  else
    echo "$json_input"
  fi
}

#######################################
# Convert Unix Epoch to Human Readable Date.
# Handles GNU/BSD date differences.
#
# Arguments:
#   1: Epoch timestamp (integer).
#
# Outputs:
#   Formatted date string.
#######################################
function __jwt_epoch_to_date() {
  local -ir epoch_timestamp="$1"
  if date --version > /dev/null 2>&1; then
    # GNU date (Linux)
    date -d "@$epoch_timestamp" '+%Y-%m-%d %H:%M:%S'
  else
    # BSD date (macOS)
    date -r "$epoch_timestamp" '+%Y-%m-%d %H:%M:%S'
  fi
}

#######################################
# Analyze and print time claims (iat, nbf, exp).
#
# Arguments:
#   1: JSON payload.
#######################################
function __jwt_check_dates() {
  local -r payload_json="$1"
  local -ir current_timestamp=$(date +%s)

  # Local colors
  local -r c_red='\033[31m'
  local -r c_green='\033[32m'
  local -r c_dim='\033[2m'
  local -r c_reset='\033[0m'

  # 1. Issued At (iat)
  local -r iat_timestamp=$(__jwt_get_json_value "$payload_json" 'iat')
  if [[ -n $iat_timestamp && $iat_timestamp != 'null' ]]; then
    local -r iat_date=$(__jwt_epoch_to_date "$iat_timestamp")
    printf '\nIssued At (iat):\n  %s %b%s%b\n' \
      "$iat_date" \
      "$c_dim" "($((current_timestamp - iat_timestamp))s ago)" "$c_reset"
  fi

  # 2. Not Before (nbf)
  local -r nbf_timestamp=$(__jwt_get_json_value "$payload_json" 'nbf')
  if [[ -n $nbf_timestamp && $nbf_timestamp != 'null' ]]; then
    local -r nbf_date=$(__jwt_epoch_to_date "$nbf_timestamp")
    local -ir nbf_diff=$((current_timestamp - nbf_timestamp))

    printf '\nNot Before (nbf):\n  %s' "$nbf_date"
    if [[ $nbf_diff -ge 0 ]]; then
      printf ' %b(Active)%b\n' "$c_green" "$c_reset"
    else
      printf ' %b(Not active yet)%b\n' "$c_red" "$c_reset"
    fi
  fi

  # 3. Expiration (exp)
  local -r exp_timestamp=$(__jwt_get_json_value "$payload_json" 'exp')
  if [[ -n $exp_timestamp && $exp_timestamp != 'null' ]]; then
    local -r exp_date=$(__jwt_epoch_to_date "$exp_timestamp")
    local -ir diff=$((exp_timestamp - current_timestamp))

    printf '\nExpiration (exp):\n  %s' "$exp_date"
    if [[ $diff -lt 0 ]]; then
      printf ' %bEXPIRED%b (%ds ago)\n' \
        "$c_red" "$c_reset" "${diff#-}"
    else
      printf ' %bVALID%b (in %ds)\n' \
        "$c_green" "$c_reset" "$diff"
    fi
  fi
}

#######################################
# Verify JWT Signature (HS256 only).
#
# Arguments:
#   1: Encoded Header string.
#   2: Encoded Payload string.
#   3: Encoded Signature string (from token).
#   4: Decoded Header JSON.
#   5: Secret key.
#
# Returns:
#   0: Signature matches.
#   1: Signature mismatch.
#######################################
function __jwt_verify_signature() {
  local -r header_base64="$1"
  local -r payload_base64="$2"
  local -r signature_base64="$3"
  local -r header_json="$4"
  local -r secret_key="$5"

  printf '\nSignature Check:\n'
  if ! __jwt_has_cmd openssl; then
    printf '  Warning: openssl not found, cannot verify.\n'
    return 0
  fi

  # Reuse extraction logic
  local -r algorithm=$(__jwt_get_json_value "$header_json" 'alg')

  if [[ $algorithm != 'HS256' ]]; then
    printf '  Warning: Algorithm %s not supported (only HS256).\n' \
      "$algorithm"
    return 0
  fi

  # Calculate Signature: HMAC-SHA256(header.payload, secret)
  local -r data="${header_base64}.${payload_base64}"

  # OpenSSL -> Binary -> Base64
  local -r calculated_signature_standard=$(printf '%s' "$data" \
    | openssl dgst -sha256 -hmac "$secret_key" -binary \
    | base64)

  local -r calculated_signature_url=$(__jwt_to_base64url \
    "$calculated_signature_standard")

  # Compare
  local -r c_red='\033[31m'
  local -r c_green='\033[32m'
  local -r c_reset='\033[0m'

  if [[ $calculated_signature_url == "$signature_base64" ]]; then
    printf '  Status: %bVERIFIED%b\n' "$c_green" "$c_reset"
    return 0
  else
    printf '  Status: %bINVALID%b\n' "$c_red" "$c_reset"
    printf '  Expected: %s\n' "$calculated_signature_url"
    printf '  Actual:   %s\n' "$signature_base64"
    return 1
  fi
}

#######################################
# Parse CLI arguments and stdin.
#
# Arguments:
#   1: Output nameref for Token (_input_token).
#   2: Output nameref for Secret (_secret_key).
#   3: Output nameref for Help Flag (_help_requested).
#   4+: CLI Arguments.
#
# Returns:
#   0: On success.
#   Non-zero: On error.
#######################################
function __jwt_parse_args() {
  local -n _input_token="$1"
  local -n _secret_key="$2"
  local -n _help_requested="$3"

  shift 3

  # Default secret from env
  _secret_key="${JWT_SECRET:-}"
  _help_requested=false

  while [[ $# -gt 0 ]]; do
    local key="$1"
    case "$key" in
      -k)
        if [[ -n ${2-} ]]; then
          _secret_key="$2"
          shift 2
        else
          __jwt_error 'Option -k requires an argument.' \
            "$JWT_ERR_USAGE" \
            || return "$?"
        fi
        ;;
      -h | --help)
        _help_requested=true
        return 0
        ;;
      -*)
        __jwt_error "Invalid option: $key" \
          "$JWT_ERR_USAGE" \
          || return "$?"
        ;;
      *)
        if [[ -z $_input_token ]]; then
          _input_token="$1"
          shift
        else
          __jwt_error "Unexpected argument: $1" \
            "$JWT_ERR_USAGE" \
            || return "$?"
        fi
        ;;
    esac
  done

  # Check stdin if no token
  if [[ -z $_input_token && ! -t 0 ]]; then
    _input_token=$(cat)
  fi

  if [[ -z $_input_token ]]; then
    __jwt_error 'No token provided. Provide as argument or via pipe.' \
      "$JWT_ERR_USAGE" \
      || return "$?"
  fi
}

#######################################
# Sanitize and split token into parts.
#
# Arguments:
#   1: Token string.
#   2: Output nameref for Header Raw.
#   3: Output nameref for Payload Raw.
#   4: Output nameref for Signature Raw.
#######################################
function __jwt_sanitize_and_split() {
  local token_string="$1"
  local -n _header_raw="$2"
  local -n _payload_raw="$3"
  local -n _signature_raw="$4"

  # Clean
  token_string="${token_string//[$'\t\r\n ']/}"

  local -a _parts
  IFS='.' read -ra _parts <<< "$token_string"

  if [[ ${#_parts[@]} -lt 2 ]]; then
    __jwt_error 'Invalid JWT format. Expected 3 parts.' \
      "$JWT_ERR_INVALID_FORMAT" \
      || return "$?"
  fi

  _header_raw="${_parts[0]}"
  _payload_raw="${_parts[1]}"
  _signature_raw="${_parts[2]:-}"
}

#######################################
# Decode Header and Payload.
#
# Arguments:
#   1: Header Raw.
#   2: Payload Raw.
#   3: Output nameref for Header Decoded.
#   4: Output nameref for Payload Decoded.
#######################################
function __jwt_decode_segments() {
  local -r header_raw_input="$1"
  local -r payload_raw_input="$2"
  local -n _header_decoded="$3"
  local -n _payload_decoded="$4"

  _header_decoded=$(__jwt_decode_part "$header_raw_input")
  if [[ -z $_header_decoded ]]; then
    __jwt_error 'Failed to decode Header.' \
      "$JWT_ERR_INVALID_FORMAT" \
      || return "$?"
  fi

  _payload_decoded=$(__jwt_decode_part "$payload_raw_input")
  if [[ -z $_payload_decoded ]]; then
    __jwt_error 'Failed to decode Payload.' \
      "$JWT_ERR_INVALID_FORMAT" \
      || return "$?"
  fi
}

#######################################
# Print decoded sections.
#
# Arguments:
#   1: Header JSON.
#   2: Payload JSON.
#######################################
function __jwt_print_report() {
  local -r header_json="$1"
  local -r payload_json="$2"
  local -r c_cyan='\033[36m'
  local -r c_magenta='\033[35m'
  local -r c_reset='\033[0m'

  printf '%b=== JWT Header ===%b\n' "$c_cyan" "$c_reset"
  __jwt_format_json "$header_json"

  printf '\n%b=== JWT Payload ===%b\n' "$c_magenta" "$c_reset"
  __jwt_format_json "$payload_json"
}

#######################################
# Handle signature verification logic.
#
# Arguments:
#   1: Secret Key.
#   2: Signature Raw.
#   3: Header Raw.
#   4: Payload Raw.
#   5: Header Decoded JSON.
#
# Returns:
#   0: On success or skip.
#   Non-zero: On error (on mismatch).
#######################################
function __jwt_handle_verification() {
  local -r secret_key_input="$1"
  local -r signature_raw_input="$2"
  local -r header_raw_input="$3"
  local -r payload_raw_input="$4"
  local -r header_decoded_input="$5"

  if [[ -n $secret_key_input ]]; then
    if [[ -z $signature_raw_input ]]; then
      printf '\nSignature Check:\n  Skipped (Token has no signature part)\n'
    else
      __jwt_verify_signature \
        "$header_raw_input" \
        "$payload_raw_input" \
        "$signature_raw_input" \
        "$header_decoded_input" \
        "$secret_key_input"
      return "$?"
    fi
  fi

  return 0
}

#######################################
# Main Orchestrator.
#
# Arguments:
#   $@: Command line arguments.
#
# Returns:
#   0: On success.
#   Non-zero: On error.
#######################################
function jwt_inspect() {
  local input_token=''
  local secret_key=''
  local help_requested=false

  # 1. Parse Args
  # Note: We pass 'help_requested' via nameref to properly halt
  # execution if -h is used, avoiding the "Empty token" error.
  __jwt_parse_args input_token secret_key help_requested "$@" \
    || return "$?"

  # 2. Check Help
  if [[ $help_requested == true ]]; then
    __jwt_usage
    return 0
  fi

  # 3. Split
  local header_raw payload_raw signature_raw
  __jwt_sanitize_and_split \
    "$input_token" header_raw payload_raw signature_raw \
    || return "$?"

  # 4. Decode
  local header_decoded payload_decoded
  __jwt_decode_segments \
    "$header_raw" "$payload_raw" header_decoded payload_decoded \
    || return "$?"

  # 5. Print & Check Dates
  __jwt_print_report "$header_decoded" "$payload_decoded"
  __jwt_check_dates "$payload_decoded"

  # 6. Verify Signature
  __jwt_handle_verification \
    "$secret_key" \
    "$signature_raw" \
    "$header_raw" \
    "$payload_raw" \
    "$header_decoded" \
    || return "$JWT_ERR_SIG_MISMATCH"
}

# Execution Guard:
# If the script is executed directly (not sourced), run the main function.
# If sourced, do nothing (just load the function).
if [[ $JWT_SCRIPT_SOURCED == false ]]; then
  jwt_inspect "$@"
  exit_code=$?
  exit "$exit_code"
fi
### End
