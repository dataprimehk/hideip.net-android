#!/bin/sh
# Builds ios/Frameworks/Libbox.xcframework from sing-box source.
#
# The framework is a build artifact and is not committed; anyone building
# the iOS app from source runs this script once. Requires Go 1.23+ and a
# full Xcode installation (not just the command line tools).
#
# The tag must match the Android libbox dependency in
# android/app/build.gradle.kts so the two platforms run the same core and
# the Dart config layer stays byte-compatible.
set -eu

SINGBOX_TAG="v1.13.12"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_DIR/ios/Frameworks"
WORK_DIR="${SINGBOX_SRC:-$(mktemp -d)/sing-box}"

if [ ! -d "$WORK_DIR/.git" ]; then
    git clone --depth 1 --branch "$SINGBOX_TAG" \
        https://github.com/SagerNet/sing-box.git "$WORK_DIR"
fi

cd "$WORK_DIR"

# sing-box builds with sagernet's gomobile fork (upstream gomobile lacks
# the -libname / per-platform tag flags). The fork version is pinned by
# the sing-box go.mod, so install it from inside the module.
go install github.com/sagernet/gomobile/cmd/gomobile \
    github.com/sagernet/gomobile/cmd/gobind
export PATH="$PATH:$(go env GOPATH)/bin"

# gomobile bind is invoked directly instead of through the upstream
# cmd/internal/build_libbox helper because the helper's tag set does not
# link on iOS and overshoots this app's needs:
#   - with_naive_outbound pulls in Chromium objects that reference
#     base::MessagePumpKqueue::InitializeFeatures(), which is not compiled
#     into the archive for iOS: the app never links.
#   - with_tailscale roughly doubles the framework; the app exposes no
#     Tailscale endpoints, and the packet tunnel extension lives under a
#     50 MB memory limit.
# The remaining tags match the protocols the app supports (QUIC for
# hysteria2/TUIC, uTLS for Reality) plus the libbox status/command plumbing.
gomobile bind -v -target ios,iossimulator -libname=box \
    -tags-not-macos=with_low_memory -trimpath -buildvcs=false \
    -ldflags "-X github.com/sagernet/sing-box/constant.Version=$SINGBOX_TAG -X internal/godebug.defaultGODEBUG=multipathtcp=0 -s -w -buildid=  -checklinkname=0" \
    -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_dhcp,badlinkname,tfogo_checklinkname0,grpcnotrace \
    ./experimental/libbox

mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/Libbox.xcframework"
mv Libbox.xcframework "$OUT_DIR/"
echo "Built $OUT_DIR/Libbox.xcframework from sing-box $SINGBOX_TAG"
