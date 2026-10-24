#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGING="$ROOT/packaging/linux"
BUILD="${VPX_BUILD_DIR:-$ROOT/build/linux}"
DIST="${VPX_DIST_DIR:-$ROOT/dist}"
JOBS="${JOBS:-$(nproc)}"
GODOT="${GODOT:-godot}"

FFMPEG_VERSION="${FFMPEG_VERSION:-9.0.1}"
NASM_VERSION="2.16.03"
DSD_NEXUS_COMMIT="b3f443d4c42ccf52806eb57def3b3a34805714bd"
EXT_REPO="https://github.com/EIRTeam/EIRTeam.FFmpeg"
EXT_COMMIT="0b21297b3c3a740963698fa3396bc3c8d387dd72"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

USE_PREBUILT_EXT=0
CLEAN=0

usage() {
	cat <<EOF
Usage: $(basename "$0") [--prebuilt-ext] [--clean] [-j N]
  --prebuilt-ext  package addons/ffmpeg/linux64 .so as is instead of compiling the extension
  --clean         delete $BUILD first
  -j N            parallel jobs (default $JOBS)
Env: GODOT (editor binary), FFMPEG_VERSION, GLIBC_TARGET, VPX_BUILD_DIR, VPX_DIST_DIR
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--prebuilt-ext) USE_PREBUILT_EXT=1 ;;
		--clean) CLEAN=1 ;;
		-j) JOBS="$2"; shift ;;
		-h|--help) usage; exit 0 ;;
		*) usage; exit 1 ;;
	esac
	shift
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }

for tool in git curl tar make cmake cc c++ pkg-config python3 rsync objdump strip bzip2 xz openssl "$GODOT"; do
	command -v "$tool" >/dev/null || die "missing tool: $tool"
done
for module in dav1d libva libva-drm libdrm openssl srt zlib vulkan libjpeg dvdread dvdnav libxml-2.0; do
	pkg-config --exists "$module" || die "missing development package: $module"
done

[ "$CLEAN" = 1 ] && rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST" "$ROOT/build"
touch "$ROOT/build/.gdignore"

GODOT_VERSION="$("$GODOT" --version | awk -F. '{print $1"."$2"."$3"-"$4}')"
[[ "$GODOT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[a-z0-9]+$ ]] || die "cannot parse Godot version: $("$GODOT" --version)"
VPX_BUILD_NUMBER="${VPX_BUILD_NUMBER:-$("$ROOT/packaging/bump-build.sh")}"

VPX_VERSION="$(python3 "$ROOT/packaging/release_version.py" "${VPX_VERSION:-}")"

TOOLS="$BUILD/tools"
VENV="$BUILD/venv"
FFMPEG_SRC="$BUILD/ffmpeg-$FFMPEG_VERSION"
FFMPEG_PREFIX="$BUILD/ffmpeg"
EXT="$BUILD/EIRTeam.FFmpeg"
TEMPLATE="$BUILD/templates/$GODOT_VERSION/linux_release.x86_64"
STAGE="$BUILD/stage"
APPDIR="$BUILD/AppDir"
mkdir -p "$TOOLS/bin"
export PATH="$TOOLS/bin:$VENV/bin:$PATH"

step "Python tools (scons, patchelf)"
if [ ! -x "$VENV/bin/scons" ] || [ ! -x "$VENV/bin/patchelf" ] || [ ! -x "$VENV/bin/meson" ]; then
	python3 -m venv "$VENV"
	"$VENV/bin/pip" install -q --upgrade pip
	"$VENV/bin/pip" install -q scons patchelf meson ninja
fi

if ! command -v nasm >/dev/null; then
	step "nasm $NASM_VERSION"
	curl -fL --retry 3 -o "$BUILD/nasm.tar.xz" "https://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.xz"
	tar -xf "$BUILD/nasm.tar.xz" -C "$BUILD"
	(cd "$BUILD/nasm-$NASM_VERSION" && ./configure -q --prefix="$TOOLS" && make -s -j"$JOBS" && make -s install)
fi

step "DSD Nexus"
DSD_SRC="$BUILD/dsd-nexus"
DSD_BUILD="$BUILD/dsd-nexus-build"
DSD_PREFIX="$BUILD/dsd-nexus-prefix"
DSD_ID3DEV_CACHE="$BUILD/id3dev-src"
if [ ! -d "$DSD_SRC/.git" ]; then
	git init -q "$DSD_SRC"
	git -C "$DSD_SRC" remote add origin https://github.com/wichers/dsd-nexus.git
fi
if [ "$(git -C "$DSD_SRC" rev-parse -q --verify HEAD || true)" != "$DSD_NEXUS_COMMIT" ]; then
	git -C "$DSD_SRC" fetch -q --depth 1 origin "$DSD_NEXUS_COMMIT"
	git -C "$DSD_SRC" checkout -q --force FETCH_HEAD
fi
git -C "$DSD_SRC" reset -q --hard "$DSD_NEXUS_COMMIT"
python3 - "$DSD_SRC/external/libdsdpcm/binding/dsdpcm_engine.cpp" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
if "void log_printf(const char *fmt, ...)" not in text:
    text += "\n#include <cstdarg>\n#include <cstdio>\nvoid log_printf(const char *fmt, ...) { va_list args; va_start(args, fmt); vfprintf(stderr, fmt, args); va_end(args); }\n"
path.write_text(text)
PYEOF
if [ ! -f "$DSD_ID3DEV_CACHE/id3dependencies/LinkedListLib/src/LinkedList.c" ] \
	&& [ -f "$DSD_BUILD/_deps/id3dev-src/id3dependencies/LinkedListLib/src/LinkedList.c" ]; then
	cp -a "$DSD_BUILD/_deps/id3dev-src" "$DSD_ID3DEV_CACHE"
elif [ ! -f "$DSD_ID3DEV_CACHE/id3dependencies/LinkedListLib/src/LinkedList.c" ] \
	&& [ -f "$ROOT/build/windows/src/dsd-nexus-build/_deps/id3dev-src/id3dependencies/LinkedListLib/src/LinkedList.c" ]; then
	cp -a "$ROOT/build/windows/src/dsd-nexus-build/_deps/id3dev-src" "$DSD_ID3DEV_CACHE"
fi
rm -rf "$DSD_BUILD" "$DSD_PREFIX"
DSD_ID3DEV_ARGS=()
if [ -f "$DSD_ID3DEV_CACHE/id3dependencies/LinkedListLib/src/LinkedList.c" ] \
	&& [ -f "$DSD_ID3DEV_CACHE/id3dependencies/HashTableLib/src/hashTable.c" ]; then
	DSD_ID3DEV_ARGS+=("-DFETCHCONTENT_SOURCE_DIR_ID3DEV=$DSD_ID3DEV_CACHE")
fi
python3 - "$DSD_SRC/CMakeLists.txt" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
marker = "project(dsd-nexus VERSION 0.1.83 LANGUAGES C CXX)"
if "find_package(Threads REQUIRED)" not in text:
    text = text.replace(marker, marker + "\nfind_package(Threads REQUIRED)")
path.write_text(text)
PYEOF
GLIBC_TARGET="${GLIBC_TARGET:-2.38}"
GLIBC_COMPAT="$BUILD/glibc-compat.h"
objdump -T "$(cc -print-file-name=libm.so.6)" | awk -v target="$GLIBC_TARGET" '
	function key(v, parts) { split(v, parts, "[_.]"); return parts[2] * 1000 + parts[3] }
	BEGIN { split(target, t, "."); limit = t[1] * 1000 + t[2] }
	NF > 2 && $(NF - 1) ~ /GLIBC_/ {
		version = $(NF - 1); name = $NF
		if (version ~ /^\(/) { gsub(/[()]/, "", version); hidden[name] = version } else current[name] = version
	}
	END {
		for (name in current)
			if ((name in hidden) && key(current[name]) > limit && name !~ /fromfp/)
				printf "__asm__(\".symver %s,%s@%s\");\n", name, name, hidden[name]
	}' | sort >"$GLIBC_COMPAT.new"
cmp -s "$GLIBC_COMPAT.new" "$GLIBC_COMPAT" && rm "$GLIBC_COMPAT.new" || mv "$GLIBC_COMPAT.new" "$GLIBC_COMPAT"
cmake -S "$DSD_SRC" -B "$DSD_BUILD" -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$DSD_PREFIX" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DBUILD_SHARED_LIBS=ON -DBUILD_EXTRAS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF -DBUILD_PS3DRIVE=OFF \
	-DDSDPCM_USE_TBB=OFF -DDSDPCM_USE_IPP=OFF -DCMAKE_DISABLE_FIND_PACKAGE_FLAC=TRUE \
	-DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=TRUE -DDSDPIPE_FETCH_FLAC=OFF \
	-DCMAKE_C_FLAGS="-include $GLIBC_COMPAT" -DCMAKE_CXX_FLAGS="-include $GLIBC_COMPAT" \
	"${DSD_ID3DEV_ARGS[@]}"
cmake --build "$DSD_BUILD" --target libdsd --parallel "$JOBS"
mkdir -p "$DSD_PREFIX/lib" "$DSD_PREFIX/include"
install -m 755 "$DSD_BUILD/lib/Release/libdsd.so" "$DSD_PREFIX/lib/libdsd.so"
cp -a "$DSD_SRC/libs/libsacdvfs/include/." "$DSD_PREFIX/include/"
mkdir -p "$BUILD/site_scons"
cat >"$BUILD/site_scons/site_init.py" <<EOF
import SCons.Environment

_base_init = SCons.Environment.Base.__init__


def _init_with_glibc_compat(self, *args, **kwargs):
    _base_init(self, *args, **kwargs)
    self.Append(CCFLAGS=["-include", "$GLIBC_COMPAT"])


SCons.Environment.Base.__init__ = _init_with_glibc_compat
EOF

python3 "$ROOT/packaging/build-rubberband.py" --work "$BUILD" --prefix "$FFMPEG_PREFIX" --meson "$VENV/bin/meson" --compat-header "$GLIBC_COMPAT" --jobs "$JOBS"

export PKG_CONFIG_PATH="$FFMPEG_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

FFMPEG_CONFIGURE=(
	--prefix="$FFMPEG_PREFIX"
	--enable-shared --disable-static --enable-pic
	--disable-debug --disable-doc --disable-ffplay
	--disable-autodetect
	--enable-version3 --enable-openssl --enable-libsrt --enable-libxml2
	--enable-gpl --enable-librubberband --pkg-config-flags=--static --extra-libs="-lstdc++ -lm" --enable-libdvdread --enable-libdvdnav --enable-demuxer=dvdvideo
	--enable-pthreads --enable-iconv --enable-zlib --enable-bzlib
	--enable-vaapi --enable-libdrm --enable-vulkan
	--enable-libdav1d
	--enable-x86asm
	--extra-cflags="-include $GLIBC_COMPAT"
)
FFMPEG_STAMP="$FFMPEG_PREFIX/.stamp"
FFMPEG_KEY="$FFMPEG_VERSION ${FFMPEG_CONFIGURE[*]} $(md5sum <"$GLIBC_COMPAT") $(cat "$FFMPEG_PREFIX/.rubberband-stamp")"
if [ "$(cat "$FFMPEG_STAMP" 2>/dev/null)" != "$FFMPEG_KEY" ]; then
	step "FFmpeg $FFMPEG_VERSION"
	if [ ! -d "$FFMPEG_SRC" ]; then
		curl -fL --retry 3 -o "$BUILD/ffmpeg.tar.xz" "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
		tar -xf "$BUILD/ffmpeg.tar.xz" -C "$BUILD"
		rm "$BUILD/ffmpeg.tar.xz"
	fi
	(cd "$FFMPEG_SRC" && ./configure "${FFMPEG_CONFIGURE[@]}" >/dev/null && make -s -j"$JOBS" && make -s install)
	echo "$FFMPEG_KEY" >"$FFMPEG_STAMP"
fi

EXT_SO="$EXT/gdextension_build/build/addons/ffmpeg/linux64/libgdffmpeg.linux.template_release.x86_64.so"
if [ "$USE_PREBUILT_EXT" = 1 ]; then
	EXT_SO="$ROOT/addons/ffmpeg/linux64/libgdffmpeg.linux.template_release.x86_64.so"
	step "Using prebuilt extension $EXT_SO"
else
	step "EIRTeam.FFmpeg extension + addons/ffmpeg/vpx.patch"
	if [ ! -d "$EXT/.git" ]; then
		git init -q "$EXT"
		git -C "$EXT" remote add origin "$EXT_REPO"
	fi
	if [ "$(git -C "$EXT" rev-parse -q --verify HEAD || true)" != "$EXT_COMMIT" ]; then
		git -C "$EXT" fetch -q --depth 1 origin "$EXT_COMMIT"
		git -C "$EXT" checkout -q --force FETCH_HEAD
	fi
	git -C "$EXT" submodule update -q --init --depth 1 gdextension_build/godot-cpp
	git -C "$EXT" reset -q --hard
	git -C "$EXT" clean -fdq
	git -C "$EXT" apply "$ROOT/addons/ffmpeg/vpx.patch"
	git -C "$EXT" apply "$ROOT/addons/ffmpeg/iso.patch"
	git -C "$EXT" apply "$ROOT/addons/ffmpeg/dsd-nexus.patch"
	git -C "$EXT" apply "$ROOT/addons/ffmpeg/archive.patch"
	git -C "$EXT" apply "$ROOT/addons/ffmpeg/post192.patch"
	git -C "$EXT" apply "$ROOT/addons/ffmpeg/resonance.patch"
	git -C "$EXT" apply "$ROOT/addons/ffmpeg/network.patch"
	git -C "$EXT" apply "$ROOT/addons/ffmpeg/streaming.patch"
	git -C "$EXT" apply "$ROOT/addons/ffmpeg/radio-metadata.patch"
	(cd "$EXT/gdextension_build" && scons --site-dir="$BUILD/site_scons" -j"$JOBS" platform=linux target=template_release \
		ffmpeg_path="$FFMPEG_PREFIX" dsd_path="$DSD_PREFIX" debug_symbols=no)
	(cd "$EXT/gdextension_build" && scons --site-dir="$BUILD/site_scons" -j"$JOBS" platform=linux target=template_debug \
		ffmpeg_path="$FFMPEG_PREFIX" dsd_path="$DSD_PREFIX" debug_symbols=no)
fi
[ -f "$EXT_SO" ] || die "extension not found: $EXT_SO"

if [ ! -f "$TEMPLATE" ]; then
	step "Godot $GODOT_VERSION Linux export template"
	mkdir -p "$(dirname "$TEMPLATE")"
	python3 "$PACKAGING/fetch_zip_member.py" \
		"https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/Godot_v${GODOT_VERSION}_export_templates.tpz" \
		templates/linux_release.x86_64 "$TEMPLATE.part"
	chmod +x "$TEMPLATE.part"
	mv "$TEMPLATE.part" "$TEMPLATE"
fi

step "Export project"
rsync -a --delete \
	--delete-excluded \
	--include=/project.godot --include=/openxr_action_map.tres \
	--exclude=/addons/ffmpeg/linux64 --exclude=/addons/ffmpeg/win64 \
	--include=/addons/ --include='/addons/***' \
	--include=/assets/ --include='/assets/***' \
	--include=/scenes/ --include='/scenes/***' \
	--include=/scripts/ --include='/scripts/***' \
	--include=/shaders/ --include='/shaders/***' --exclude='*' \
	"$ROOT/" "$STAGE/"
python3 "$ROOT/packaging/release_version.py" "$VPX_VERSION" --stage "$STAGE"
mkdir -p "$STAGE/addons/ffmpeg/linux64"
for slot in template_debug template_release; do
	install -m 755 "$EXT_SO" "$STAGE/addons/ffmpeg/linux64/libgdffmpeg.linux.$slot.x86_64.so"
done
cat >"$STAGE/export_presets.cfg" <<EOF
[preset.0]

name="Linux"
platform="Linux"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release="$TEMPLATE"
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
EOF
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib"
export LD_LIBRARY_PATH="$FFMPEG_PREFIX/lib:$DSD_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$GODOT" --headless --path "$STAGE" --import >"$BUILD/import.log" 2>&1 || true
"$GODOT" --headless --path "$STAGE" --export-release Linux "$APPDIR/usr/bin/vpx" >"$BUILD/export.log" 2>&1 \
	|| { tail -30 "$BUILD/export.log"; die "export failed, see $BUILD/export.log"; }
if grep -Eq 'SCRIPT ERROR: Parse Error|ERROR: Failed to load script' "$BUILD/export.log"; then
	tail -30 "$BUILD/export.log"
	die "export contains script parse errors, see $BUILD/export.log"
fi
unset LD_LIBRARY_PATH
chmod 755 "$APPDIR"/usr/bin/*.so 2>/dev/null || true
[ -f "$APPDIR/usr/bin/vpx.pck" ] || die "export produced no vpx.pck, see $BUILD/export.log"
[ -f "$APPDIR/usr/bin/libgdffmpeg.linux.template_release.x86_64.so" ] \
	|| install -m 755 "$EXT_SO" "$APPDIR/usr/bin/libgdffmpeg.linux.template_release.x86_64.so"

step "Bundle FFmpeg and libraries"
install -m 755 "$FFMPEG_PREFIX/bin/ffmpeg" "$FFMPEG_PREFIX/bin/ffprobe" "$APPDIR/usr/bin/"
cp -aL "$DSD_PREFIX"/lib/libdsd.so* "$APPDIR/usr/lib/"
cp -aL "$FFMPEG_PREFIX"/lib/lib*.so.[0-9]* "$APPDIR/usr/lib/"
find "$APPDIR/usr/lib" -name 'lib*.so.*.*' -delete

HOST_LIBS='^(ld-linux.*|libc|libm|libmvec|libdl|librt|libpthread|libresolv|libutil|libanl|libnsl|libGL.*|libEGL|libGLX.*|libGLdispatch|libOpenGL|libvulkan|libdrm.*|libgbm|libva.*|libvdpau|libOpenCL|libcuda|libnvidia.*|libX.*|libxcb.*|libwayland.*|libasound|libpulse.*|libjack|libpipewire.*|libfontconfig|libfreetype|libexpat|libudev|libsystemd|libdbus-1)\.so'
elf_files() {
	find "$APPDIR/usr/bin" "$APPDIR/usr/lib" -type f ! -name '*.pck' -exec sh -c 'head -c4 "$1" | grep -q ELF && echo "$1"' _ {} \;
}
while :; do
	added=0
	while read -r name path; do
		[[ "$name" =~ $HOST_LIBS ]] && continue
		[ -e "$APPDIR/usr/lib/$name" ] && continue
		[ -f "$path" ] || die "unresolved dependency $name"
		cp -L "$path" "$APPDIR/usr/lib/$name"
		chmod 755 "$APPDIR/usr/lib/$name"
		echo "  + $name"
		added=1
	done < <(elf_files | xargs env LD_LIBRARY_PATH="$APPDIR/usr/lib" ldd 2>/dev/null | awk '/=>/ && $3 ~ /^\// {n = $1; sub(".*/", "", n); print n, $3}' | sort -u)
	missing="$(elf_files | xargs env LD_LIBRARY_PATH="$APPDIR/usr/lib" ldd 2>/dev/null | awk '/not found/ {print $1}' | sort -u)"
	[ -z "$missing" ] || die "libraries not found: $missing"
	[ "$added" = 0 ] && break
done
for file in "$APPDIR"/usr/lib/*; do
	patchelf --force-rpath --set-rpath '$ORIGIN' "$file"
done
for file in "$APPDIR"/usr/bin/ffmpeg "$APPDIR"/usr/bin/ffprobe "$APPDIR"/usr/bin/libgdffmpeg.*.so; do
	patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "$file"
done
strip --strip-unneeded "$APPDIR"/usr/lib/* "$APPDIR"/usr/bin/ffmpeg "$APPDIR"/usr/bin/ffprobe 2>/dev/null || true

step "Verify bundle"
unresolved="$(env -u LD_LIBRARY_PATH ldd "$APPDIR"/usr/bin/libgdffmpeg.*.so "$APPDIR"/usr/bin/ffmpeg | awk '/=>/ && $3 ~ /^\// && $3 !~ /AppDir/ {n = $1; sub(".*/", "", n); print n}' | sort -u | grep -vE "$HOST_LIBS" || true)"
[ -z "$unresolved" ] || die "libraries resolve outside the AppDir: $unresolved"
"$APPDIR/usr/bin/ffprobe" -hide_banner -version | head -1
python3 "$ROOT/packaging/checks/network_protocols.py" "$APPDIR/usr/bin"
GLIBC_FLOOR="$(elf_files | xargs objdump -T 2>/dev/null | grep -oP 'GLIBC_\K[0-9.]+' | sort -Vu | tail -1)"
echo "requires glibc >= $GLIBC_FLOOR"
(( $(printf '%s\n' "$GLIBC_FLOOR" "$GLIBC_TARGET" | sort -V | tail -1 | grep -cx "$GLIBC_TARGET") )) \
	|| echo "warning: glibc floor $GLIBC_FLOOR is above GLIBC_TARGET $GLIBC_TARGET"

step "AppImage"
install -m 755 "$PACKAGING/AppRun" "$APPDIR/AppRun"
install -m 644 "$PACKAGING/vpx.desktop" "$APPDIR/vpx.desktop"
install -m 644 "$PACKAGING/vpx.png" "$APPDIR/vpx.png"
install -m 644 "$PACKAGING/vpx.png" "$APPDIR/.DirIcon"
mkdir -p "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/scalable/apps" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp "$PACKAGING/vpx.desktop" "$APPDIR/usr/share/applications/"
cp "$PACKAGING/vpx.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/"
cp "$PACKAGING/vpx.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/"
mkdir -p "$APPDIR/usr/share/licenses/VPX"
cp "$ROOT/LICENSE" "$APPDIR/usr/share/licenses/VPX/LICENSE-PolyForm-Noncommercial-1.0.0.txt"
cp "$ROOT/addons/ffmpeg/LICENSE" "$APPDIR/usr/share/licenses/VPX/EIRTeam.FFmpeg-MIT.txt"
cp "$BUILD/rubberband-4.0.0/COPYING" "$APPDIR/usr/share/licenses/VPX/RubberBand-GPL.txt"
cp "$FFMPEG_SRC/COPYING.GPLv3" "$APPDIR/usr/share/licenses/VPX/FFmpeg-GPLv3.txt"
cp /usr/share/licenses/openssl/LICENSE.txt "$APPDIR/usr/share/licenses/VPX/OpenSSL-Apache-2.0.txt"
cp /usr/share/licenses/libxml2/Copyright "$APPDIR/usr/share/licenses/VPX/libxml2-Copyright.txt"
cp /usr/share/licenses/spdx/MPL-2.0.txt "$APPDIR/usr/share/licenses/VPX/SRT-MPL-2.0.txt"
cp "$DSD_SRC/LICENSE" "$APPDIR/usr/share/licenses/VPX/DSD-Nexus-LGPL-2.1.txt"
cp /usr/share/doc/libdvdread/COPYING "$APPDIR/usr/share/licenses/VPX/libdvdread-COPYING.txt"
cp /usr/share/doc/libdvdnav/COPYING "$APPDIR/usr/share/licenses/VPX/libdvdnav-COPYING.txt"
if [ ! -x "$TOOLS/appimagetool" ]; then
	curl -fL --retry 3 -o "$TOOLS/appimagetool" "$APPIMAGETOOL_URL"
	chmod +x "$TOOLS/appimagetool"
fi
OUTPUT="$DIST/VPX-$VPX_VERSION-x86_64.AppImage"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOLS/appimagetool" --no-appstream "$APPDIR" "$OUTPUT.part" >"$BUILD/appimagetool.log" 2>&1 \
	|| { tail -30 "$BUILD/appimagetool.log"; die "appimagetool failed"; }
mv -f "$OUTPUT.part" "$OUTPUT"

step "Done"
ls -lh "$OUTPUT"
