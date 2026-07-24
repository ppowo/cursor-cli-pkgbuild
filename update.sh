#!/usr/bin/env bash
# Refresh the pinned Cursor CLI release without executing Cursor's installer.
set -euo pipefail

readonly installer_url='https://cursor.com/install'
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly pkgbuild="${script_dir}/PKGBUILD"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Remove Cursor CLI archives left over from prior pins, keeping only the one
# the PKGBUILD references (the current release).
prune_stale_archives() {
  local keep="${1:?archive to retain}" f
  shopt -s nullglob
  local found=()
  for f in "${script_dir}"/cursor-cli-*-x86_64.tar.gz; do
    [[ "${f}" == "${keep}" ]] && continue
    found+=("${f}")
  done
  shopt -u nullglob
  if ((${#found[@]})); then
    rm -f -- "${found[@]}"
    printf 'Removed %d stale archive(s)\n' "${#found[@]}"
  fi
}

for command_name in curl grep sed sort tar sha256sum mktemp rm; do
  command -v "${command_name}" >/dev/null 2>&1 || die "missing command: ${command_name}"
done
[[ -f "${pkgbuild}" ]] || die "PKGBUILD not found: ${pkgbuild}"

workdir="$(mktemp -d)"
trap 'rm -rf -- "${workdir}"' EXIT

curl_args=(
  --fail
  --silent
  --show-error
  --location
  --proto '=https'
  --tlsv1.2
  --retry 3
)

# Treat the installer strictly as text. It is never sourced or executed.
curl "${curl_args[@]}" "${installer_url}" -o "${workdir}/install.sh"

mapfile -t discovered_versions < <(
  sed -nE 's@.*https://downloads\.cursor\.com/lab/([^/]+)/\$\{OS\}/\$\{ARCH\}/agent-cli-package\.tar\.gz.*@\1@p' \
    "${workdir}/install.sh" | sort -u
)
((${#discovered_versions[@]} == 1)) || die "expected one release in the installer, found ${#discovered_versions[@]}"
readonly upstream_ver="${discovered_versions[0]}"
[[ "${upstream_ver}" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[[:alnum:]]+$ ]] || \
  die "unexpected upstream version: ${upstream_ver}"

current_upstream="$(sed -nE "s/^_upstream_ver='([^']+)'$/\1/p" "${pkgbuild}")"
current_pkgver="$(sed -nE 's/^pkgver=([^[:space:]]+)$/\1/p' "${pkgbuild}")"
current_sum="$(sed -nE "s/^sha256sums_x86_64=\('([0-9a-f]{64})'\)$/\1/p" "${pkgbuild}")"
[[ -n "${current_upstream}" && -n "${current_pkgver}" && -n "${current_sum}" ]] || \
  die 'could not parse the current PKGBUILD'

[[ "${current_pkgver}" =~ ^([0-9]{4}\.[0-9]{2}\.[0-9]{2})\.([0-9]+)\.([[:alnum:].]+)$ ]] || \
  die "unexpected current pkgver: ${current_pkgver}"
current_date="${BASH_REMATCH[1]}"
current_revision="${BASH_REMATCH[2]}"
release_date="${upstream_ver%%-*}"
release_id="${upstream_ver#*-}"

[[ "${release_date}" < "${current_date}" ]] && \
  die "installer advertises older release ${upstream_ver}; refusing to downgrade"

if [[ "${upstream_ver}" == "${current_upstream}" ]]; then
  new_pkgver="${current_pkgver}"
elif [[ "${release_date}" == "${current_date}" ]]; then
  new_pkgver="${release_date}.$((current_revision + 1)).${release_id}"
else
  new_pkgver="${release_date}.1.${release_id}"
fi

archive_name="cursor-cli-${upstream_ver}-x86_64.tar.gz"
archive_path="${script_dir}/${archive_name}"

# Avoid downloading the roughly 80 MiB archive when the local pinned copy is valid.
if [[ "${upstream_ver}" == "${current_upstream}" && -f "${archive_path}" ]]; then
  local_sum="$(sha256sum "${archive_path}" | awk '{print $1}')"
  if [[ "${local_sum}" == "${current_sum}" ]]; then
    prune_stale_archives "${archive_path}"
    printf 'Already at latest Cursor CLI release: %s\n' "${upstream_ver}"
    exit 0
  fi
fi

archive_url="https://downloads.cursor.com/lab/${upstream_ver}/linux/x64/agent-cli-package.tar.gz"
printf 'Downloading %s\n' "${archive_url}"
curl "${curl_args[@]}" "${archive_url}" -o "${workdir}/${archive_name}"

tar -tzf "${workdir}/${archive_name}" > "${workdir}/archive.list"
if grep -Eq '(^/|(^|/)\.\.(/|$))' "${workdir}/archive.list"; then
  die 'archive contains an unsafe path'
fi
for required_path in \
  dist-package/cursor-agent \
  dist-package/index.js \
  dist-package/node; do
  grep -Fxq "${required_path}" "${workdir}/archive.list" || \
    die "archive is missing ${required_path}"
done

new_sum="$(sha256sum "${workdir}/${archive_name}" | awk '{print $1}')"
if [[ "${upstream_ver}" == "${current_upstream}" && "${new_sum}" != "${current_sum}" ]]; then
  die "upstream archive changed in place (${current_sum} -> ${new_sum}); inspect it manually"
fi

updated_pkgbuild="${workdir}/PKGBUILD"
cp -- "${pkgbuild}" "${updated_pkgbuild}"
sed -i -E \
  -e "s@^_upstream_ver=.*@_upstream_ver='${upstream_ver}'@" \
  -e "s@^sha256sums_x86_64=.*@sha256sums_x86_64=('${new_sum}')@" \
  "${updated_pkgbuild}"
if [[ "${upstream_ver}" != "${current_upstream}" ]]; then
  sed -i -E \
    -e "s@^pkgver=.*@pkgver=${new_pkgver}@" \
    -e 's@^pkgrel=.*@pkgrel=1@' \
    "${updated_pkgbuild}"
fi

grep -Fxq "_upstream_ver='${upstream_ver}'" "${updated_pkgbuild}" || die 'failed to update _upstream_ver'
grep -Fxq "pkgver=${new_pkgver}" "${updated_pkgbuild}" || die 'failed to update pkgver'
grep -Fxq "sha256sums_x86_64=('${new_sum}')" "${updated_pkgbuild}" || die 'failed to update checksum'

mv -f -- "${workdir}/${archive_name}" "${archive_path}"
chmod --reference="${pkgbuild}" "${updated_pkgbuild}"
mv -f -- "${updated_pkgbuild}" "${pkgbuild}"
prune_stale_archives "${archive_path}"

printf 'Pinned Cursor CLI %s as package version %s\n' "${upstream_ver}" "${new_pkgver}"
printf 'SHA-256: %s\n' "${new_sum}"
printf 'Next: cd %q && makepkg -s\n' "${script_dir}"
