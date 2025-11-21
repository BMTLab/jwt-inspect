# jwt-inspect

A small Bash CLI and function to decode and inspect JSON Web Tokens (JWT) directly in your terminal.

> It separates the header and payload, pretty‑prints the JSON, inspects time claims (`iat`, `nbf`, `exp`), and can verify HS256 signatures using a shared secret. Everything runs locally on your machine - no tokens are sent to external services.

---

## Features

1. **Local and offline**

   * All parsing, decoding, and verification is done locally.
   * No network requests; safer than pasting tokens into web-based debuggers.

2. **Readable JWT breakdown**

   * Decodes Base64Url-encoded header and payload.
   * Pretty‑prints JSON via `jq` (or Python's `json.tool` as a fallback).
   * Clear sections for:

     * `=== JWT Header ===`
     * `=== JWT Payload ===`

3. **Time claim analysis**

   * Extracts and inspects these standard claims (if present):

     * `iat` - Issued At
     * `nbf` - Not Before
     * `exp` - Expiration Time
   * Prints human‑readable times and simple status information:

     * `EXPIRED` / `VALID` for `exp`
     * `Active` / `Not active yet` for `nbf`
   * Works with both GNU `date` (Linux) and BSD `date` (macOS).

4. **Signature verification (HS256)**

   * Supports HS256 (`alg: "HS256"`) signature verification using OpenSSL.
   * Compares the token's signature with a locally computed HMAC‑SHA256.
   * Shows `Status: VERIFIED` or `Status: INVALID` and prints expected vs actual signature.

5. **Flexible secret input**

   * Secret key can be provided in two ways:

     * `-k <secret>` CLI option
     * `JWT_SECRET` environment variable

6. **Safe CLI function or standalone script**

   * Can be **executed** as a standalone script (`./jwt-inspect.sh ...`).
   * Can be **sourced** into your shell to define the `jwt_inspect` function without exiting the shell on error.

> [!TIP]
> For sensitive secrets, prefer the `JWT_SECRET` environment variable over the `-k` flag, 
> to avoid leaking the secret into shell history.

---

## Requirements

* Bash
* `base64` (coreutils)
* `openssl` - required for HS256 signature verification

Optional but strongly recommended:

* `jq` - for pretty JSON formatting and colors
* `python3` - used as a fallback JSON formatter (`python3 -m json.tool`)

The script is otherwise self‑contained and does not require any external JWT libraries.

---

## Installation

### 1. Clone or download

Download `jwt-inspect.sh` or clone the repository that contains it.

### 2. Make the script executable

```bash
chmod +x jwt-inspect.sh
```

You can now run it directly:

```bash
./jwt-inspect.sh '<your-jwt-here>'
```

### 3. (Optional) Install into your PATH

To use `jwt_inspect` as a global command, move or symlink the script into a directory on your `PATH`:

```bash
mv jwt-inspect.sh ~/.local/bin/jwt-inspect
chmod +x ~/.local/bin/jwt-inspect
```

Then you can call:

```bash
jwt-inspect '<your-jwt-here>'
```

### 4. (Optional) Source into your shell

If you prefer `jwt_inspect` as a shell function (without starting a new process and without exiting the shell on errors), you can source the script:

```bash
source /path/to/jwt-inspect.sh

# now jwt_inspect is available as a function
jwt_inspect '<your-jwt-here>'
```

When sourced, the script sets `JWT_SCRIPT_SOURCED=true` and `jwt_inspect` will use `return` instead of `exit` on errors.

---

## Quick start

### Decode a JWT without verifying the signature

```bash
jwt-inspect 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMn0.invalid-signature'
```

Example output:

<img width="1352" height="1276" alt="image" src="https://github.com/user-attachments/assets/c744d6b3-4cff-4433-a2f3-4a4338f264f4" />

```text
=== JWT Header ===
{
  "alg": "HS256",
  "typ": "JWT"
}

=== JWT Payload ===
{
  "sub": "1234567890",
  "name": "John Doe",
  "admin": true,
  "iat": 1516239022
}

Issued At (iat):
  2018-01-18 02:30:22 (247512306s ago)

Signature Check:
  Status: INVALID
  Expected: <calculated-signature>
  Actual:   <signature-from-token>
```

(Exact timestamps and signatures will differ.)

### Verify signature with a shared secret

Provide the secret with `-k`:

```bash
jwt-inspect -k 'a-string-secret-at-least-256-bits-long' '<your-jwt-here>'
```

Or use the `JWT_SECRET` environment variable:

```bash
export JWT_SECRET='a-string-secret-at-least-256-bits-long'
jwt-inspect '<your-jwt-here>'
```

If the algorithm is `HS256` and the signature is correct, you will see:

```text
Signature Check:
  Status: VERIFIED
```

---

## Usage

The script defines a single user-facing entry point: the `jwt_inspect` function (also called when the script is executed as `jwt-inspect.sh`).

Basic syntax:

```bash
jwt_inspect [-k <secret>] <token>

echo '<token>' | jwt_inspect [-k <secret>]
```

### Options

* `-k <secret>`  - Shared secret key for HS256 signature verification.

  * If omitted, the script checks the `JWT_SECRET` environment variable.
* `-h`, `--help` - Show usage information.

### Token input

The token can be supplied:

1. As a positional argument:

   ```bash
   jwt_inspect '<jwt-token-here>'
   ```

2. Via stdin (for example, piping from another command or pasting):

   ```bash
   echo '<jwt-token-here>' | jwt_inspect
   ```

Whitespace characters (spaces, tabs, newlines) are stripped from the token before parsing, so you can safely paste multi-line tokens.

> [!IMPORTANT]
> `jwt_inspect` expects a standard JWT with **three dot-separated parts**
> (`header.payload.signature`). Tokens with fewer parts are treated as invalid and cause an error.

---

## Time claim analysis

If the payload contains any of the standard numeric time claims, the script will decode them and print a brief status.

### `iat` - Issued At

* Prints the UTC timestamp in `YYYY-MM-DD HH:MM:SS` format.
* Shows how many seconds ago the token was issued.

### `nbf` - Not Before

* Prints the UTC timestamp.
* Compares it with the current time:

  * `Active` (green) - `nbf` is in the past.
  * `Not active yet` (red) - `nbf` is in the future.

### `exp` - Expiration Time

* Prints the UTC timestamp.
* Compares it with the current time:

  * `EXPIRED` (red) - `exp` is in the past.
  * `VALID` (green) - token is still within the validity window.
* Also prints how many seconds ago it expired, or in how many seconds it will expire.

> [!NOTE]
> Time comparisons use the local system clock (`date +%s`).
> Ensure your system time is accurate if you rely on these checks.

---

## Signature verification

The script currently supports **HS256** (`alg: "HS256"`) verification using OpenSSL:

1. Concatenates `header_raw.payload_raw` as the signing input.
2. Computes `HMAC-SHA256` using the provided secret key.
3. Encodes the result in standard Base64, then converts to Base64Url.
4. Compares the Base64Url string with the signature part from the token.

If `openssl` is missing, signature verification is skipped with a warning.

If the algorithm in the header is not `HS256`, verification is also skipped with a warning:

```text
Signature Check:
  Warning: Algorithm RS256 not supported (only HS256).
```

> [!WARNING]
> This script does **not** implement asymmetric algorithms (e.g., RS256) or key management. 
> It is intended as a lightweight helper for HS256 tokens only.

---

## Security considerations

* **Secrets in shell history**

  * Passing a secret key via `-k` may cause it to be stored in shell history (`~/.bash_history`, etc.).
  * For sensitive keys, prefer:

    ```bash
    export JWT_SECRET='your-secret-here'
    jwt_inspect '<token>'
    ```

* **Local verification vs. online tools**

  * `jwt_inspect` is safer than web-based JWT debuggers because tokens never leave your machine.
  * However, you are still responsible for keeping your secret keys safe and using the tool in trusted environments.

* **Parsing limitations**

  * Fallback JSON extraction without `jq` is intentionally simple and only
    reliable for scalar values. For robust output, installing `jq` is strongly recommended.

---

## Exit codes

The script uses deterministic exit codes so you can integrate it into other tools and CI pipelines:

* `0` - Success
* `1` (`JWT_ERR_GENERAL`) - General error
* `2` (`JWT_ERR_USAGE`) - Invalid usage or arguments
* `3` (`JWT_ERR_INVALID_FORMAT`) - Not a valid JWT structure
* `4` (`JWT_ERR_SIG_MISMATCH`) - Signature verification failed

When sourced, `jwt_inspect` **returns** these codes instead of exiting the shell.

---

## Examples for scripting

### Check if a token is expired

```bash
if jwt_inspect "$TOKEN" >/dev/null; then
  echo "Token is structurally valid"
else
  echo "Token is invalid or expired (see output above)" >&2
fi
```

### Verify token and fail a script on signature mismatch

```bash
export JWT_SECRET='my-secret'

if ! jwt_inspect "$TOKEN" >/dev/null; then
  echo "JWT failed verification" >&2
  exit 1
fi
```

---

## License & disclaimer

This project is licensed under the [MIT License](./LICENSE).

> [!IMPORTANT]
> This tool is intended for debugging and inspection. It does not replace a production-grade JWT validation library or framework.
> Always validate tokens using well-maintained libraries in your application stack.

---

## Contributing

Issues and pull requests are welcome.
If you propose new features (e.g., additional algorithms or output formats), please include concrete examples and a brief rationale
so `jwt-inspect` can remain small, understandable, and focused on its core job :lock_with_ink_pen:
