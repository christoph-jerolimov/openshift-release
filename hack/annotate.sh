#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

base="$( dirname "${BASH_SOURCE[0]}" )/.."

# The following is an array of all the 4.x releases that have ReleaseConfig definitions, sorted by version from Highest to Lowest:
# [4.11, 4.10, 4.9, 4.8, ...]
releases=( $(ls "${base}/core-services/release-controller/_releases/" | grep -Eo "4\.[0-9]+" | sort -Vr | uniq) )

# Stolen from https://github.com/kubermatic/kubermatic/blob/00c0da788d618a4fbf3ddf1e9655c8a3a06d0a28/hack/lib.sh#L41 https://github.com/kubermatic/kubermatic/blob/00c0da788d618a4fbf3ddf1e9655c8a3a06d0a28/hack/lib.sh#L41
retry() {
  retries=$1
  shift

  count=0
  delay=2
  until "$@"; do
    rc=$?
    count=$((count + 1))
    if [ $count -lt "$retries" ]; then
      echo "Retry $count/$retries exited $rc, retrying in $delay seconds..." > /dev/stderr
      sleep $delay
    else
      echo "Retry $count/$retries exited $rc, no more retries left." > /dev/stderr
      return $rc
    fi
    delay=$((delay * 2))
  done
  return 0
}

function annotate() {
	local namespace="$1"
	local name="$2"
	local private="${4:-}" # empty string by default
	local conf="${base}/core-services/release-controller/_releases/release-$3"

	if [[ -n "${private}" ]]; then
        conf="${base}/core-services/release-controller/_releases/priv/release-$3"
    fi

	if [[ -s "${conf}" ]]; then
		echo "${conf}"
		jq . <"${conf}"

		# If this is a configuration for a private release controller, enforce that all ProwJob
		# names include "priv". This attempts to ensure that no on introduces a ProwJob without
		# "hidden: true" to the verification steps of embargoed release payloads.
		if [[ -n "${private}" ]]; then
			local nonpriv_hits=$(cat ${conf} | jq -r '.verify | keys[] as $k | (.[$k] | .prowJob.name)' | grep -v priv)
			if [[ -n "${nonpriv_hits}" ]]; then
				echo "${conf} contains prowJob name without 'priv' substring ; Please use naming convention to ensure embargoed releases are not tested publicly."
				exit 1
			fi
		fi

		retry 10 oc annotate -n "${namespace}" "is/${name}" "release.openshift.io/config=$( cat "${conf}" | jq -c . )" --overwrite
	fi
}

# It has been decided that the release-controller should no longer display information for the older, EOL, releases on the
# Release Status page.  The following logic will iterate through the first 7 releases of the array and annotate the
# imagestreams accordingly. The older imagestreams, that are no longer being annotated, will still remain on the Release
# Status page until someone manually removes the "release.openshift.io/config" annotation from them.
#
# Currently, the "latest" release is 4.11.  So, the releases that will be annotated by this logic will be:
#   4.11, 4.10, 4.9, 4.8, 4.7, 4.6, 4.5
# At the point that 4.12 gets introduced, this logic will annotate the following releases:
#   4.12, 4.11, 4.10, 4.9, 4.8, 4.7, 4.6
# and so on.
for release in ${releases[@]:0:7}; do
	annotate "origin" "${release}" "okd-${release}.json"
	annotate "ocp" "${release}" "ocp-${release}-ci.json"
	annotate "ocp" "${release}-art-latest" "ocp-${release}.json"
	annotate "ocp-s390x" "${release}-art-latest-s390x" "ocp-${release}-s390x.json"
	annotate "ocp-ppc64le" "${release}-art-latest-ppc64le" "ocp-${release}-ppc64le.json"
	annotate "ocp-arm64" "${release}-art-latest-arm64" "ocp-${release}-arm64.json"
	annotate "ocp-multi" "${release}-art-latest-multi" "ocp-${release}-multi.json"
	annotate "ocp-priv" "${release}-art-latest-priv" "ocp-${release}.json" "private"
	annotate "ocp-s390x-priv" "${release}-art-latest-s390x-priv" "ocp-${release}-s390x.json" "private"
	annotate "ocp-ppc64le-priv" "${release}-art-latest-ppc64le-priv" "ocp-${release}-ppc64le.json" "private"
	annotate "ocp-arm64-priv" "${release}-art-latest-arm64-priv" "ocp-${release}-arm64.json" "private"
	annotate "ocp-multi-priv" "${release}-art-latest-multi-priv" "ocp-${release}-multi.json" "private"
done

annotate "origin" "release" "okd-4.y-stable.json"
annotate "ocp" "release" "ocp-4.y-stable.json"
annotate "ocp-s390x" "release-s390x" "ocp-4.y-stable-s390x.json"
annotate "ocp-ppc64le" "release-ppc64le" "ocp-4.y-stable-ppc64le.json"
annotate "ocp-arm64" "release-arm64" "ocp-4.y-stable-arm64.json"
annotate "ocp-multi" "release-multi" "ocp-4.y-stable-multi.json"
