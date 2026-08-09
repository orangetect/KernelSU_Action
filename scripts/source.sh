#!/usr/bin/env bash
# Fetch the kernel source tree.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORKSPACE=${WORKSPACE:?WORKSPACE must be set}
KERNEL_DIR="${WORKSPACE}/android-kernel"

group "Cloning kernel source"
info "${KERNEL_SOURCE} @ ${KERNEL_SOURCE_BRANCH}"

ref_exists "$KERNEL_SOURCE" "$KERNEL_SOURCE_BRANCH" \
	|| die "branch/tag '${KERNEL_SOURCE_BRANCH}' does not exist in ${KERNEL_SOURCE}"

rm -rf "$KERNEL_DIR"
retry 3 git clone -q --recursive --depth=1 \
	-b "$KERNEL_SOURCE_BRANCH" "$KERNEL_SOURCE" "$KERNEL_DIR" \
	|| die "failed to clone ${KERNEL_SOURCE}"

# KernelSU forks compute their version from the commit count, and several
# read it straight out of the enclosing git repo. A depth-1 clone reports 1
# commit, which produces a nonsense version. Unshallow just enough to count.
if [ -f "${KERNEL_DIR}/.git/shallow" ]; then
	debug "kernel tree is shallow; that is fine for building"
fi

KVER=$(kernel_version "$KERNEL_DIR") \
	|| die "could not read VERSION/PATCHLEVEL from ${KERNEL_DIR}/Makefile -- is this a kernel tree?"
export_env KERNEL_VERSION "$KVER"
export_env KERNEL_DIR "$KERNEL_DIR"
ok "kernel source ready (Linux ${KVER})"
summary "| Kernel | \`${KERNEL_SOURCE##*/}\` @ \`${KERNEL_SOURCE_BRANCH}\` (Linux ${KVER}) |"

# Some device-maintained kernel branches already carry a complete root
# implementation. Treat them as a first-class option so the workflow does
# not inject a second, conflicting copy through kernel/setup.sh.
if [ "${KSU_VARIANT:-none}" = "source" ]; then
	[ -d "${KERNEL_DIR}/drivers/kernelsu" ] \
		|| die "KSU_VARIANT=source requires drivers/kernelsu in the selected kernel branch"
	grep -q '^CONFIG_KSU=y' "${KERNEL_DIR}/arch/${ARCH:-arm64}/configs/${KERNEL_CONFIG}" \
		|| die "KSU_VARIANT=source requires CONFIG_KSU=y in ${KERNEL_CONFIG}"
	export_env KSU_NAME "ReSukiSU (bundled)"
	export_env KSU_REF_RESOLVED "${KERNEL_SOURCE_BRANCH}"
	export_env KSU_VERSION_LABEL "${KERNEL_SOURCE_BRANCH}"
	export_env KSU_HOOK_MODE_RESOLVED "none"
	export_env UPLOADNAME "-ReSukiSU_bundled"
	summary "| KernelSU | \`ReSukiSU (bundled in kernel source)\` |"
fi

# LOCALVERSION is used purely to decorate artifact names.
if is_true "${ADD_LOCALVERSION_TO_FILENAME:-false}" && [ -f "${KERNEL_DIR}/localversion" ]; then
	export_env LOCALVERSION "$(cat "${KERNEL_DIR}/localversion")"
else
	export_env LOCALVERSION ""
fi
endgroup
