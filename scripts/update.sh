#!/usr/bin/env bash
# Pin the newest complete T3 Code nightly release in sources.json.
#
# Only prebuilt upstream release assets are referenced; nothing is built from
# source. The file is left untouched when no newer complete nightly exists.
#
# Environment:
#   T3CODE_NIGHTLY_TAG  optional, pin this exact tag (e.g. v0.0.43-nightly.20260928.2402)
set -euo pipefail

repo=pingdotgg/t3code
sources=sources.json
tag_override="${T3CODE_NIGHTLY_TAG:-}"

[[ -f flake.nix ]] || { echo "Run from the repository root." >&2; exit 1; }
for tool in curl jq nix; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

github() {
  curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" "$@"
}

current=""
[[ -f "$sources" ]] && current="$(jq -r '.version // ""' "$sources")"

releases="$(github "https://api.github.com/repos/$repo/releases?per_page=100")"

# Select the newest nightly (by date and build number, not API order) whose
# six required assets are all fully uploaded. Preview and stable releases are
# ignored. Emits {latest, candidate}; candidate is null when nothing newer.
selection="$(jq -c --arg current "$current" --arg tag "$tag_override" '
  def key: capture("-nightly\\.(?<d>[0-9]{8})\\.(?<n>[0-9]+)$") | [(.d | tonumber), (.n | tonumber)];
  def names($v): {
    cli: {
      "aarch64-darwin": "t3-\($v)-darwin-arm64.tar.gz",
      "x86_64-linux": "t3-\($v)-linux-x64.tar.gz",
      "aarch64-linux": "t3-\($v)-linux-arm64.tar.gz"
    },
    desktop: {
      "aarch64-darwin": "T3-Code-\($v)-arm64.zip",
      "x86_64-linux": "T3-Code-\($v)-x86_64.AppImage",
      "aarch64-linux": "T3-Code-\($v)-arm64.AppImage"
    }
  };
  def resolve:
    (.tag_name | ltrimstr("v")) as $v
    | (.assets | map(select(.state == "uploaded")) | INDEX(.name)) as $a
    | {
        tag: .tag_name,
        version: $v,
        rev: .target_commitish,
        sums: ($a["SHA256SUMS"].browser_download_url // null),
        files: (names($v) | map_values(map_values(
          $a[.] | if . == null then null else {url: .browser_download_url, digest: (.digest // null)} end
        )))
      };
  def complete: [.files[][]] | all(. != null);

  ([.[]
    | select((.draft | not) and (.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+-nightly\\.[0-9]{8}\\.[0-9]+$")))
    | select($tag == "" or .tag_name == $tag)]
   | sort_by(.tag_name | key) | reverse) as $nightlies
  | (if $current == "" then [0, 0] else ("v" + $current | key) end) as $pinned
  | {
      latest: ($nightlies[0].tag_name // null),
      candidate: (
        [$nightlies[] | resolve | select(complete)]
        | map(select($tag != "" or (.tag | key) > $pinned))
        | first // null
      )
    }
' <<<"$releases")"

latest="$(jq -r '.latest // empty' <<<"$selection")"
[[ -n "$latest" ]] || { echo "No nightly release found${tag_override:+ for $tag_override}." >&2; exit 1; }

if [[ "$(jq -r '.candidate == null' <<<"$selection")" == true ]]; then
  if [[ "v$current" == "$latest" ]]; then
    echo "Already pinned to the newest nightly ($current)."
  else
    echo "Newest nightly $latest is incomplete or not newer; keeping ${current:-nothing pinned}."
  fi
  exit 0
fi

candidate="$(jq -c .candidate <<<"$selection")"
version="$(jq -r .version <<<"$candidate")"
echo "Pinning T3 Code $version."

sums=""
sums_url="$(jq -r '.sums // empty' <<<"$candidate")"
if [[ -n "$sums_url" ]]; then
  sums="$(curl -fsSL --retry 3 "$sums_url")"
else
  echo "warning: $version has no SHA256SUMS; relying on GitHub asset digests." >&2
fi

hashes='{}'
while IFS=$'\t' read -r kind system url digest; do
  name="${url##*/}"
  hex=""
  if [[ "$digest" == sha256:* ]]; then
    hex="${digest#sha256:}"
  fi

  if [[ -n "$sums" ]]; then
    listed="$(awk -v f="$name" '$2 == f || $2 == "*" f { print $1 }' <<<"$sums")"
    if [[ -n "$listed" ]]; then
      if [[ -n "$hex" && "$listed" != "$hex" ]]; then
        echo "Digest mismatch for $name: GitHub=$hex SHA256SUMS=$listed" >&2
        exit 1
      fi
      hex="$listed"
    elif [[ "$kind" == cli ]]; then
      echo "$name is missing from SHA256SUMS." >&2
      exit 1
    fi
  fi

  if [[ -n "$hex" ]]; then
    sri="$(nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri "$hex")"
  else
    echo "No published digest for $name; downloading to hash it." >&2
    sri="$(nix --extra-experimental-features nix-command store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"
  fi

  echo "  $kind $system: $name"
  hashes="$(jq -c --arg k "$kind/$system" --arg v "$sri" '. + {($k): $v}' <<<"$hashes")"
done < <(jq -r '.files | to_entries[] | .key as $kind | .value | to_entries[]
  | [$kind, .key, .value.url, (.value.digest // "")] | @tsv' <<<"$candidate")

tmp="$(mktemp "$sources.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
jq -n --argjson c "$candidate" --argjson h "$hashes" '
  def pin($kind): $c.files[$kind] | with_entries(.value = {url: .value.url, hash: $h["\($kind)/\(.key)"]});
  {version: $c.version, tag: $c.tag, rev: $c.rev, cli: pin("cli"), desktop: pin("desktop")}
' >"$tmp"
mv "$tmp" "$sources"
trap - EXIT

echo "Pinned T3 Code $version."
