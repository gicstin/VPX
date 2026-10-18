#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGING="$ROOT/packaging/windows"
BUILD="${VPX_BUILD_DIR:-$ROOT/build/windows}"
DIST="${VPX_DIST_DIR:-$ROOT/dist}"
JOBS="${JOBS:-$(nproc)}"
GODOT="${GODOT:-godot}"

LLVM_MINGW_VERSION="20260922"
FFMPEG_VERSION="${FFMPEG_VERSION:-9.0.1}"
DAV1D_VERSION="1.5.4"
ZLIB_VERSION="1.3.1"
JPEG_VERSION="3.2.0"
NASM_VERSION="2.16.03"
BUSYBOX_TAG="FRP-6075-g169694ebd"
EXT_REPO="https://github.com/EIRTeam/EIRTeam.FFmpeg"
EXT_COMMIT="0b21297b3c3a740963698fa3396bc3c8d387dd72"
TRIPLE="x86_64-w64-mingw32"
LIBDVDREAD_COMMIT="0f30df53125b564ef45903714403ce0a1e6c5e9e"
LIBDVDNAV_COMMIT="8147ccd35e5aae4afdd21171cf7b6b4d8f179d28"
DSD_NEXUS_COMMIT="b3f443d4c42ccf52806eb57def3b3a34805714bd"
LIBICONV_VERSION="1.18"

CLEAN=0
while [ $# -gt 0 ]; do
	case "$1" in
		--clean) CLEAN=1 ;;
		-j) JOBS="$2"; shift ;;
		-h|--help) echo "Usage: $(basename "$0") [--clean] [-j N]"; exit 0 ;;
		*) echo "unknown option $1" >&2; exit 1 ;;
	esac
	shift
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }
fetch() {
	[ -f "$2" ] || { curl -fL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; }
}

for tool in git curl tar make cmake cc c++ pkg-config python3 rsync bzip2 xz "$GODOT"; do
	command -v "$tool" >/dev/null || die "missing tool: $tool"
done
[ -f /usr/include/vulkan/vulkan.h ] || die "missing Vulkan headers (vulkan-headers package)"

[ "$CLEAN" = 1 ] && rm -rf "$BUILD"
mkdir -p "$BUILD/src" "$DIST" "$ROOT/build"
touch "$ROOT/build/.gdignore"

GODOT_VERSION="$("$GODOT" --version | awk -F. '{print $1"."$2"."$3"-"$4}')"
[[ "$GODOT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[a-z0-9]+$ ]] || die "cannot parse Godot version: $("$GODOT" --version)"
VPX_BUILD_NUMBER="${VPX_BUILD_NUMBER:-$(grep -oP '^const BUILD := \K[0-9]+' "$ROOT/scripts/log.gd")}"

VPX_VERSION="$(python3 "$ROOT/packaging/release_version.py" "${VPX_VERSION:-}")"
VPX_NUMERIC_VERSION="${VPX_VERSION%%[-+]*}"

TOOLS="$BUILD/tools"
VENV="$BUILD/venv"
PREFIX="$BUILD/prefix"
SRC="$BUILD/src"
EXT="$BUILD/EIRTeam.FFmpeg"
TEMPLATE="$BUILD/templates/$GODOT_VERSION/windows_release_x86_64.exe"
STAGE="$BUILD/stage"
PAYLOAD="$BUILD/payload"
mkdir -p "$TOOLS/bin" "$PREFIX/include" "$PREFIX/lib"
export PATH="$TOOLS/llvm-mingw/bin:$TOOLS/bin:$VENV/bin:$PATH"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH=""

if [ ! -x "$TOOLS/llvm-mingw/bin/$TRIPLE-clang" ]; then
	step "llvm-mingw $LLVM_MINGW_VERSION"
	name="llvm-mingw-$LLVM_MINGW_VERSION-ucrt-ubuntu-22.04-x86_64"
	fetch "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VERSION/$name.tar.xz" "$SRC/$name.tar.xz"
	rm -rf "$TOOLS/llvm-mingw" && tar -xf "$SRC/$name.tar.xz" -C "$TOOLS" && mv "$TOOLS/$name" "$TOOLS/llvm-mingw"
fi

step "Python tools (scons, meson, ninja)"
if [ ! -x "$VENV/bin/scons" ] || [ ! -x "$VENV/bin/meson" ]; then
	python3 -m venv "$VENV"
	"$VENV/bin/pip" install -q --upgrade pip
	"$VENV/bin/pip" install -q scons meson ninja
fi

if ! command -v nasm >/dev/null; then
	step "nasm $NASM_VERSION"
	fetch "https://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.xz" "$SRC/nasm.tar.xz"
	tar -xf "$SRC/nasm.tar.xz" -C "$SRC"
	(cd "$SRC/nasm-$NASM_VERSION" && ./configure -q --prefix="$TOOLS" && make -s -j"$JOBS" && make -s install)
fi

if [ ! -f "$PREFIX/bin/busybox.exe" ]; then
	step "busybox-w32 $BUSYBOX_TAG"
	fetch "https://github.com/rmyorston/busybox-w32/archive/refs/tags/$BUSYBOX_TAG.tar.gz" "$SRC/busybox.tar.gz"
	rm -rf "$SRC/busybox-w32-$BUSYBOX_TAG" && tar -xf "$SRC/busybox.tar.gz" -C "$SRC"
	make -s -C "$SRC/busybox-w32-$BUSYBOX_TAG" mingw64u_defconfig >/dev/null
	make -s -C "$SRC/busybox-w32-$BUSYBOX_TAG" -j"$JOBS" CROSS_COMPILE="$TRIPLE-" CC="$TRIPLE-clang" HOSTCC=cc >/dev/null
	mkdir -p "$PREFIX/bin"
	install -m 755 "$SRC/busybox-w32-$BUSYBOX_TAG/busybox.exe" "$PREFIX/bin/busybox.exe"
fi

if [ ! -f "$PREFIX/lib/libz.a" ]; then
	step "zlib $ZLIB_VERSION"
	fetch "https://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz" "$SRC/zlib.tar.gz"
	rm -rf "$SRC/zlib-$ZLIB_VERSION" && tar -xf "$SRC/zlib.tar.gz" -C "$SRC"
	make -s -C "$SRC/zlib-$ZLIB_VERSION" -f win32/Makefile.gcc PREFIX="$TRIPLE-" CC="$TRIPLE-clang" -j"$JOBS" libz.a
	make -s -C "$SRC/zlib-$ZLIB_VERSION" -f win32/Makefile.gcc PREFIX="$TRIPLE-" \
		INCLUDE_PATH="$PREFIX/include" LIBRARY_PATH="$PREFIX/lib" BINARY_PATH="$PREFIX/bin" install
	mkdir -p "$PREFIX/lib/pkgconfig"
	printf 'prefix=%s\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: zlib\nDescription: zlib\nVersion: %s\nLibs: -L${libdir} -lz\nCflags: -I${includedir}\n' \
		"$PREFIX" "$ZLIB_VERSION" >"$PREFIX/lib/pkgconfig/zlib.pc"
fi

if [ ! -f "$PREFIX/lib/libiconv.a" ]; then
	step "libiconv $LIBICONV_VERSION"
	fetch "https://mirrors.kernel.org/gnu/libiconv/libiconv-$LIBICONV_VERSION.tar.gz" "$SRC/libiconv.tar.gz"
	tar -xf "$SRC/libiconv.tar.gz" -C "$SRC"
	(cd "$SRC/libiconv-$LIBICONV_VERSION" && ./configure --host="$TRIPLE" --prefix="$PREFIX" \
		CC="$TRIPLE-clang" --enable-static --disable-shared >/dev/null && make -s -j"$JOBS" && make -s install)
fi

step "DSD Nexus"
DSD_SRC="$SRC/dsd-nexus"
DSD_BUILD="$SRC/dsd-nexus-build"
DSD_PREFIX="$SRC/dsd-nexus-prefix"
DSD_ID3DEV_CACHE="$SRC/id3dev-src"
if [ ! -d "$DSD_SRC/.git" ]; then
	git init -q "$DSD_SRC"
	git -C "$DSD_SRC" remote add origin https://github.com/wichers/dsd-nexus.git
fi
if [ "$(git -C "$DSD_SRC" rev-parse -q --verify HEAD || true)" != "$DSD_NEXUS_COMMIT" ]; then
	git -C "$DSD_SRC" fetch -q --depth 1 origin "$DSD_NEXUS_COMMIT"
	git -C "$DSD_SRC" checkout -q --force FETCH_HEAD
fi
git -C "$DSD_SRC" reset -q --hard "$DSD_NEXUS_COMMIT"
if [ ! -f "$DSD_ID3DEV_CACHE/id3dependencies/LinkedListLib/src/LinkedList.c" ] \
	&& [ -f "$ROOT/build/linux/id3dev-src/id3dependencies/LinkedListLib/src/LinkedList.c" ]; then
	cp -a "$ROOT/build/linux/id3dev-src" "$DSD_ID3DEV_CACHE"
fi
if [ ! -f "$DSD_ID3DEV_CACHE/id3dependencies/LinkedListLib/src/LinkedList.c" ] \
	&& [ -f "$ROOT/build/linux/dsd-nexus-build/_deps/id3dev-src/id3dependencies/LinkedListLib/src/LinkedList.c" ]; then
	cp -a "$ROOT/build/linux/dsd-nexus-build/_deps/id3dev-src" "$DSD_ID3DEV_CACHE"
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
python3 - "$DSD_SRC/libs/libsautil/CMakeLists.txt" "$TOOLS/llvm-mingw/generic-w64-mingw32/include/time.h" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("elseif(NOT WIN32)\n    # Force include system time.h first to prevent local time.h from shadowing it", "else()\n    # Force include system time.h first to prevent local time.h from shadowing it", 1)
text = text.replace("if(APPLE)\n        # macOS: system headers are inside the SDK, find the path via xcrun", f"if(WIN32)\n        target_compile_options(sautil PRIVATE -include {sys.argv[2]})\n    elseif(APPLE)\n        # macOS: system headers are inside the SDK, find the path via xcrun", 1)
path.write_text(text)
PYEOF
python3 - "$DSD_SRC/libs/libsautil/buffer_internal.h" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text().replace("#ifdef __APPLE__\n#include \"c11threads.h\"", "#if defined(__APPLE__) || defined(_WIN32)\n#include \"c11threads.h\"", 1)
path.write_text(text)
PYEOF
python3 - "$DSD_SRC/libs/libsautil/configs/win/x64/config.h" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("#define HAVE_GETSTDHANDLE 1", "#define HAVE_GETSTDHANDLE 0")
text = text.replace("#define HAVE_SETCONSOLETEXTATTRIBUTE 1", "#define HAVE_SETCONSOLETEXTATTRIBUTE 0")
path.write_text(text)
PYEOF
python3 - "$DSD_SRC/libs/libsautil/c11threads.h" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("#include <time.h>", "#include <time.h>\n#ifdef _WIN32\n#include <windows.h>\n#endif", 1)
text = text.replace("\tif(nanosleep(ts_in, rem_out) < 0) {\n\t\tif(errno == EINTR) return -1;\n\t\treturn -2;\n\t}\n\treturn 0;", "\t#ifdef _WIN32\n\tSleep((DWORD)(ts_in->tv_sec * 1000 + (ts_in->tv_nsec + 999999) / 1000000));\n\treturn 0;\n\t#else\n\tif(nanosleep(ts_in, rem_out) < 0) {\n\t\tif(errno == EINTR) return -1;\n\t\treturn -2;\n\t}\n\treturn 0;\n\t#endif", 1)
path.write_text(text)
PYEOF
python3 - "$DSD_SRC" <<'PYEOF'
from pathlib import Path
import sys
root = Path(sys.argv[1])
for path in root.rglob("*"):
    if path.suffix in {".c", ".h"}:
        text = path.read_text(errors="ignore")
        updated = text.replace("#include <threads.h>", '#include "c11threads.h"')
        if updated != text:
            path.write_text(updated)
PYEOF
python3 - "$DSD_SRC/libs/libsacdvfs/src/sacd_overlay_iso.c" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
if "#include <time.h>" not in text:
    text = text.replace('#include "sacd_overlay_internal.h"', '#include "sacd_overlay_internal.h"\n\n#include <time.h>', 1)
path.write_text(text)
PYEOF
python3 - "$DSD_SRC/CMakeLists.txt" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("        set(CMAKE_SHARED_LINKER_FLAGS_RELEASE \"${CMAKE_SHARED_LINKER_FLAGS_RELEASE} -Wl,-dead_strip\")\n    else()", "        set(CMAKE_SHARED_LINKER_FLAGS_RELEASE \"${CMAKE_SHARED_LINKER_FLAGS_RELEASE} -Wl,-dead_strip\")\n    elseif(WIN32)\n    else()", 1)
text = text.replace("if(IPO_SUPPORTED)\n        set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)", "if(IPO_SUPPORTED AND NOT WIN32)\n        set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)", 1)
text = text.replace("target_link_libraries(libdsd PRIVATE dsdpcm_core nanopb id3dev tinycsocket)", "target_link_libraries(libdsd PRIVATE dsdpcm_core nanopb id3dev tinycsocket Threads::Threads)", 1)
path.write_text(text)
PYEOF
python3 - "$DSD_SRC/external/libdsdpcm/binding/dsdpcm_engine.cpp" <<'PYEOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
if "void log_printf(const char *fmt, ...)" not in text:
    text += "\n#include <cstdarg>\n#include <cstdio>\nvoid log_printf(const char *fmt, ...) { va_list args; va_start(args, fmt); vfprintf(stderr, fmt, args); va_end(args); }\n"
path.write_text(text)
PYEOF
cat >"$BUILD/dsd-nexus-toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_C_COMPILER "$TRIPLE-clang")
set(CMAKE_CXX_COMPILER "$TRIPLE-clang++")
set(CMAKE_RC_COMPILER "$TRIPLE-windres")
set(CMAKE_AR "$TRIPLE-ar")
set(CMAKE_RANLIB "$TRIPLE-ranlib")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
cmake -S "$DSD_SRC" -B "$DSD_BUILD" -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_TOOLCHAIN_FILE="$BUILD/dsd-nexus-toolchain.cmake" -DCMAKE_INSTALL_PREFIX="$DSD_PREFIX" \
	-DCMAKE_C_FLAGS="-I$DSD_SRC/libs/libsautil -include $TOOLS/llvm-mingw/generic-w64-mingw32/include/time.h" \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=ON -DBUILD_EXTRAS=OFF \
	-DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF -DBUILD_PS3DRIVE=OFF -DDSDPCM_USE_TBB=OFF -DDSDPCM_USE_IPP=OFF \
	-DCMAKE_DISABLE_FIND_PACKAGE_FLAC=TRUE -DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=TRUE -DDSDPIPE_FETCH_FLAC=OFF \
	"${DSD_ID3DEV_ARGS[@]}"
cmake --build "$DSD_BUILD" --target libdsd --parallel "$JOBS"
mkdir -p "$DSD_PREFIX/lib" "$DSD_PREFIX/bin" "$DSD_PREFIX/include"
install -m 644 "$DSD_BUILD/lib/Release/libdsd.dll.a" "$DSD_PREFIX/lib/libdsd.dll.a"
install -m 755 "$DSD_BUILD/bin/Release/libdsd.dll" "$DSD_PREFIX/bin/libdsd.dll"
cp -a "$DSD_SRC/libs/libsacdvfs/include/." "$DSD_PREFIX/include/"

cat >"$BUILD/cross.meson" <<EOF
[binaries]
c = '$TRIPLE-clang'
cpp = '$TRIPLE-clang++'
ar = '$TRIPLE-ar'
strip = '$TRIPLE-strip'
windres = '$TRIPLE-windres'
nasm = '$(command -v nasm)'
pkg-config = 'pkg-config'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

build_meson_dependency() {
	local name="$1" repo="$2" commit="$3"
	local source="$SRC/$name" build="$SRC/$name/build"
	local meson_options=(-Denable_docs=false -Dextra_checks=false)
	if [ "$name" = "libdvdread" ]; then
		meson_options+=(-Dlibdvdcss=disabled -Ddlfcn=builtin)
	fi
	if [ ! -d "$source/.git" ]; then
		git init -q "$source"
		git -C "$source" remote add origin "$repo"
	fi
	if [ "$(git -C "$source" rev-parse -q --verify HEAD || true)" != "$commit" ]; then
		git -C "$source" fetch -q --depth 1 origin "$commit"
		git -C "$source" checkout -q --force FETCH_HEAD
	fi
	if [ -f "$build/meson-private/coredata.dat" ]; then
		"$VENV/bin/meson" setup --reconfigure "$build" "$source" --cross-file "$BUILD/cross.meson" \
			--prefix="$PREFIX" --libdir=lib --default-library=static "${meson_options[@]}"
	else
		"$VENV/bin/meson" setup "$build" "$source" --cross-file "$BUILD/cross.meson" \
			--prefix="$PREFIX" --libdir=lib --default-library=static "${meson_options[@]}"
	fi
	ninja -C "$build" install >/dev/null
}

step "libdvdread and libdvdnav"
build_meson_dependency libdvdread https://code.videolan.org/videolan/libdvdread.git "$LIBDVDREAD_COMMIT"
build_meson_dependency libdvdnav https://code.videolan.org/videolan/libdvdnav.git "$LIBDVDNAV_COMMIT"

if [ ! -f "$PREFIX/lib/libdav1d.a" ]; then
	step "dav1d $DAV1D_VERSION"
	fetch "https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.gz" "$SRC/dav1d.tar.gz"
	rm -rf "$SRC/dav1d-$DAV1D_VERSION" && tar -xf "$SRC/dav1d.tar.gz" -C "$SRC"
	meson setup "$SRC/dav1d-$DAV1D_VERSION/build" "$SRC/dav1d-$DAV1D_VERSION" --cross-file "$BUILD/cross.meson" \
		--prefix="$PREFIX" --libdir=lib --buildtype=release --default-library=static \
		-Denable_tools=false -Denable_tests=false -Denable_examples=false >/dev/null
	ninja -C "$SRC/dav1d-$DAV1D_VERSION/build" install >/dev/null
fi

if [ ! -f "$PREFIX/lib/libjpeg.a" ]; then
	step "libjpeg-turbo $JPEG_VERSION"
	fetch "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$JPEG_VERSION/libjpeg-turbo-$JPEG_VERSION.tar.gz" "$SRC/jpeg.tar.gz"
	rm -rf "$SRC/libjpeg-turbo-$JPEG_VERSION" && tar -xf "$SRC/jpeg.tar.gz" -C "$SRC"
	cmake -S "$SRC/libjpeg-turbo-$JPEG_VERSION" -B "$SRC/libjpeg-turbo-$JPEG_VERSION/build" -G Ninja \
		-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=AMD64 \
		-DCMAKE_C_COMPILER="$TRIPLE-clang" -DCMAKE_RC_COMPILER="$TRIPLE-windres" \
		-DCMAKE_ASM_NASM_COMPILER="$(command -v nasm)" -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
		-DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF >/dev/null
	ninja -C "$SRC/libjpeg-turbo-$JPEG_VERSION/build" install >/dev/null
fi

if [ ! -d "$PREFIX/include/vulkan" ]; then
	cp -r /usr/include/vulkan "$PREFIX/include/"
	[ -d /usr/include/vk_video ] && cp -r /usr/include/vk_video "$PREFIX/include/"
fi

python3 "$ROOT/packaging/build-rubberband.py" --work "$SRC" --prefix "$PREFIX" --meson "$VENV/bin/meson" --cross-file "$BUILD/cross.meson" --jobs "$JOBS"

FFMPEG_CONFIGURE=(
	--prefix="$PREFIX"
	--target-os=mingw32 --arch=x86_64 --enable-cross-compile
	--cross-prefix="$TRIPLE-" --cc="$TRIPLE-clang" --cxx="$TRIPLE-clang++"
	--pkg-config=pkg-config --pkg-config-flags=--static
	--enable-shared --disable-static
	--disable-debug --disable-doc --disable-ffplay --disable-avdevice
	--disable-autodetect
	--enable-gpl --enable-librubberband --extra-libs=-lc++ --enable-libdvdread --enable-libdvdnav --enable-demuxer=dvdvideo
	--enable-w32threads --enable-zlib
	--enable-d3d11va --enable-dxva2 --enable-vulkan
	--enable-libdav1d --enable-schannel
	--enable-x86asm
	--extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib"
)
FFMPEG_STAMP="$PREFIX/.ffmpeg-stamp"
FFMPEG_KEY="$FFMPEG_VERSION $LIBDVDREAD_COMMIT $LIBDVDNAV_COMMIT ${FFMPEG_CONFIGURE[*]} $(cat "$PREFIX/.rubberband-stamp")"
if [ "$(cat "$FFMPEG_STAMP" 2>/dev/null)" != "$FFMPEG_KEY" ]; then
	step "FFmpeg $FFMPEG_VERSION"
	fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" "$SRC/ffmpeg-$FFMPEG_VERSION.tar.xz"
	rm -rf "$SRC/ffmpeg-$FFMPEG_VERSION" && tar -xf "$SRC/ffmpeg-$FFMPEG_VERSION.tar.xz" -C "$SRC"
	(cd "$SRC/ffmpeg-$FFMPEG_VERSION" && ./configure "${FFMPEG_CONFIGURE[@]}" >"$BUILD/ffmpeg-configure.log" 2>&1 \
		|| { tail -20 "$BUILD/ffmpeg-configure.log"; tail -40 ffbuild/config.log; exit 1; })
	make -s -C "$SRC/ffmpeg-$FFMPEG_VERSION" -j"$JOBS"
	make -s -C "$SRC/ffmpeg-$FFMPEG_VERSION" install
	echo "$FFMPEG_KEY" >"$FFMPEG_STAMP"
fi

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
mkdir -p "$BUILD/site_scons"
cat >"$BUILD/site_scons/site_init.py" <<'PYEOF'
import os

import SCons.Environment

_base_init = SCons.Environment.Base.__init__


def _init_with_host_path(self, *args, **kwargs):
    _base_init(self, *args, **kwargs)
    self["ENV"]["PATH"] = os.environ["PATH"]


SCons.Environment.Base.__init__ = _init_with_host_path
PYEOF
(cd "$EXT/gdextension_build" && scons --site-dir="$BUILD/site_scons" -j"$JOBS" platform=windows use_mingw=yes use_static_cpp=no \
	target=template_release ffmpeg_path="$PREFIX" dsd_path="$DSD_PREFIX" debug_symbols=no)
(cd "$EXT/gdextension_build" && scons --site-dir="$BUILD/site_scons" -j"$JOBS" platform=windows use_mingw=yes use_static_cpp=no \
	target=template_debug ffmpeg_path="$PREFIX" dsd_path="$DSD_PREFIX" debug_symbols=no)
EXT_DLL="$EXT/gdextension_build/build/addons/ffmpeg/win64/libgdffmpeg.windows.template_release.x86_64.dll"
EXT_DEBUG_DLL="$EXT/gdextension_build/build/addons/ffmpeg/win64/libgdffmpeg.windows.template_debug.x86_64.dll"
[ -f "$EXT_DLL" ] || die "extension not found: $EXT_DLL"
[ -f "$EXT_DEBUG_DLL" ] || die "debug extension not found: $EXT_DEBUG_DLL"

if [ ! -f "$TEMPLATE" ]; then
	step "Godot $GODOT_VERSION Windows export template"
	mkdir -p "$(dirname "$TEMPLATE")"
	python3 "$ROOT/packaging/linux/fetch_zip_member.py" \
		"https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/Godot_v${GODOT_VERSION}_export_templates.tpz" \
		templates/windows_release_x86_64.exe "$TEMPLATE.part"
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
HOST_EXT=""
for dir in "$ROOT/addons/ffmpeg/linux64" "$ROOT/build/linux/stage/addons/ffmpeg/linux64"; do
	[ -f "$dir/libgdffmpeg.linux.template_debug.x86_64.so" ] && { HOST_EXT="$dir"; break; }
done
[ -n "$HOST_EXT" ] || die "Linux extension needed for export; run packaging/linux/build-appimage.sh first"
mkdir -p "$STAGE/addons/ffmpeg/linux64"
cp -a "$HOST_EXT"/. "$STAGE/addons/ffmpeg/linux64/"
mkdir -p "$STAGE/addons/ffmpeg/win64"
install -m 644 "$EXT_DLL" "$STAGE/addons/ffmpeg/win64/libgdffmpeg.windows.template_release.x86_64.dll"
install -m 644 "$EXT_DEBUG_DLL" "$STAGE/addons/ffmpeg/win64/libgdffmpeg.windows.template_debug.x86_64.dll"
python3 - "$STAGE/addons/ffmpeg/ffmpeg.gdextension" <<'PYEOF'
import re
import sys

path = sys.argv[1]
text = open(path).read()
text = re.sub(r"windows\.x86_64 =\s*\{[^}]*\}", "windows.x86_64 = {}", text)
open(path, "w").write(text)
PYEOF
cp "$ROOT/packaging/linux/vpx.svg" "$STAGE/vpx_icon.svg"
sed -i 's|^\[application\]$|[application]\n\nconfig/icon="res://vpx_icon.svg"|' "$STAGE/project.godot"
cat >"$STAGE/export_presets.cfg" <<PRESET
[preset.0]

name="Windows"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="addons/ffmpeg/linux64/*"
export_path=""
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release="$TEMPLATE"
debug/export_console_wrapper=0
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
application/modify_resources=true
application/icon="$PACKAGING/vpx.ico"
application/product_name="VPX"
application/file_description="VPX Video Player XR"
application/file_version="$VPX_NUMERIC_VERSION.0"
application/product_version="$VPX_NUMERIC_VERSION.0"
PRESET
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
"$GODOT" --headless --path "$STAGE" --import >"$BUILD/import.log" 2>&1 || true
"$GODOT" --headless --path "$STAGE" --export-release Windows "$PAYLOAD/VPX.exe" >"$BUILD/export.log" 2>&1 \
	|| { tail -30 "$BUILD/export.log"; die "export failed, see $BUILD/export.log"; }
if grep -Eq 'SCRIPT ERROR: Parse Error|ERROR: Failed to load script' "$BUILD/export.log"; then
	tail -30 "$BUILD/export.log"
	die "export contains script parse errors, see $BUILD/export.log"
fi
[ -f "$PAYLOAD/VPX.exe" ] || die "export produced no VPX.exe, see $BUILD/export.log"
[ -f "$PAYLOAD/libgdffmpeg.windows.template_release.x86_64.dll" ] || install -m 644 "$EXT_DLL" "$PAYLOAD/"

step "Payload"
cp "$PREFIX"/bin/*.dll "$PREFIX"/bin/ffmpeg.exe "$PREFIX"/bin/ffprobe.exe "$PREFIX"/bin/busybox.exe "$PAYLOAD/"
cp "$DSD_PREFIX"/bin/*.dll "$PAYLOAD/"
cp "$TOOLS/llvm-mingw/$TRIPLE/bin/libc++.dll" "$TOOLS/llvm-mingw/$TRIPLE/bin/libunwind.dll" "$PAYLOAD/"
cp "$TOOLS/llvm-mingw/$TRIPLE/bin/libwinpthread-1.dll" "$PAYLOAD/"
cp "$ROOT/LICENSE" "$PAYLOAD/LICENSE.txt"
mkdir -p "$PAYLOAD/licenses"
install -m 644 "$ROOT/addons/ffmpeg/LICENSE" "$PAYLOAD/licenses/EIRTeam.FFmpeg-MIT.txt"
install -m 644 "$SRC/rubberband-4.0.0/COPYING" "$PAYLOAD/licenses/RubberBand-GPL.txt"
install -m 644 "$SRC/ffmpeg-$FFMPEG_VERSION/COPYING.GPLv2" "$PAYLOAD/licenses/FFmpeg-GPLv2.txt"
install -m 644 "$SRC/libdvdread/COPYING" "$PAYLOAD/licenses/libdvdread-COPYING.txt"
install -m 644 "$SRC/libdvdnav/COPYING" "$PAYLOAD/licenses/libdvdnav-COPYING.txt"
install -m 644 "$DSD_SRC/LICENSE" "$PAYLOAD/licenses/DSD-Nexus-LGPL-2.1.txt"
if [ -f "$SRC/libiconv-$LIBICONV_VERSION/COPYING.LIB" ]; then
	install -m 644 "$SRC/libiconv-$LIBICONV_VERSION/COPYING.LIB" "$PAYLOAD/licenses/libiconv-LGPL.txt"
else
	install -m 644 "$DSD_SRC/LICENSE" "$PAYLOAD/licenses/libiconv-LGPL.txt"
fi
$TRIPLE-strip --strip-unneeded "$PAYLOAD"/*.dll "$PAYLOAD"/ffmpeg.exe "$PAYLOAD"/ffprobe.exe
missing=""
for file in "$PAYLOAD"/ffmpeg.exe "$PAYLOAD"/ffprobe.exe "$PAYLOAD"/busybox.exe "$PAYLOAD"/*.dll; do
	for dll in $($TRIPLE-objdump -p "$file" | awk '/DLL Name:/ {print $3}'); do
		[[ "${dll,,}" =~ ^(api-ms-win-|kernel32|user32|gdi32|advapi32|shell32|ole32|oleaut32|ws2_32|bcrypt|secur32|crypt32|ncrypt|mfplat|mfuuid|strmiids|psapi|shlwapi|comdlg32|winmm|imm32|dwmapi|dxgi|d3d11|d3d12|d3dcompiler|dwrite|version|setupapi|winhttp|iphlpapi|hid|dbghelp|avrt|opengl32|uxtheme|ntdll|userenv|wtsapi32|dinput8|xinput|cfgmgr32|rpcrt4|powrprof|propsys|mmdevapi|ksuser|msvcrt|shcore|wsock32|uiautomationcore|mf|mfreadwrite|ole32) ]] && continue
		[ -f "$PAYLOAD/$dll" ] || missing="$missing $(basename "$file"):$dll"
	done
done
[ -z "$missing" ] || die "missing DLLs:$missing"

step "Launcher"
cat >"$BUILD/launcher.rc" <<RC
1 ICON "$PACKAGING/vpx.ico"
1 VERSIONINFO
FILEVERSION ${VPX_NUMERIC_VERSION//./,},0
PRODUCTVERSION ${VPX_NUMERIC_VERSION//./,},0
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904b0"
    BEGIN
      VALUE "FileDescription", "VPX Video Player XR"
      VALUE "ProductName", "VPX"
      VALUE "FileVersion", "$VPX_NUMERIC_VERSION.0"
      VALUE "ProductVersion", "$VPX_VERSION"
      VALUE "OriginalFilename", "VPX.exe"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1200
  END
END
RC
$TRIPLE-windres "$BUILD/launcher.rc" -O coff -o "$BUILD/launcher.res"
$TRIPLE-clang -O2 -municode -mwindows -I"$PREFIX/include" "$PACKAGING/launcher.c" "$BUILD/launcher.res" \
	-L"$PREFIX/lib" -l:libz.a -lshell32 -o "$BUILD/launcher.exe"
$TRIPLE-strip "$BUILD/launcher.exe"
$TRIPLE-clang -O2 -municode "$PACKAGING/nice.c" -o "$PAYLOAD/nice.exe"
$TRIPLE-strip "$PAYLOAD/nice.exe"
OUTPUT="$DIST/VPX-$VPX_VERSION-windows-x86_64.exe"
python3 "$PACKAGING/pack.py" "$BUILD/launcher.exe" "$PAYLOAD" "$OUTPUT"

step "Done"
ls -lh "$OUTPUT"
