#!/bin/sh
# Build gitten without replacing the system Git installation.
set -eu

usage () {
	cat <<'USAGE'
Usage: sh install.sh [--prefix DIR] [--bin-dir DIR] [--jobs N] [--ref REF] [--source DIR]

Defaults:
  --prefix  $HOME/.local/opt/gitten
  --bin-dir $HOME/.local/bin
  --jobs    4
  --ref     main

--source builds a local checkout instead of downloading from GitHub.
Requires a C compiler, make, zlib development files, Perl, Python 3, and tar.
Optional curl/expat development files enable HTTP(S) transport and DAV pushes.
USAGE
}
fail () { printf '%s\n' "gitten installer: $*" >&2; exit 1; }

prefix=${HOME:?HOME must be set}/.local/opt/gitten
bin_dir=$HOME/.local/bin
jobs=4
ref=main
source_dir=
while [ "$#" -gt 0 ]; do
	case "$1" in
		-h|--help) usage; exit 0 ;;
		--prefix|--bin-dir|--jobs|--ref|--source)
			[ "$#" -ge 2 ] && [ -n "$2" ] || fail "$1 requires a value"
			case "$1" in
				--prefix) prefix=$2 ;;
				--bin-dir) bin_dir=$2 ;;
				--jobs) jobs=$2 ;;
				--ref) ref=$2 ;;
				--source) source_dir=$2 ;;
			esac
			shift 2 ;;
		*) fail "unknown option: $1 (use --help)" ;;
	esac
done
case "$jobs" in ''|*[!0-9]*) fail '--jobs must be a positive integer' ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || fail '--jobs must be a positive integer'
case "$ref" in *[!a-zA-Z0-9._/-]*) fail 'unsupported characters in --ref' ;; esac
case "$(uname -s)" in Linux|Darwin) ;; *) fail 'supported platforms: Linux and macOS' ;; esac
cc=${CC:-cc}
make_command=${MAKE:-make}
for command in "$cc" "$make_command" perl python3 tar; do
	command -v "$command" >/dev/null 2>&1 || fail "missing dependency: $command"
done
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/gitten-install.XXXXXXXX")
trap 'rm -rf "$work_dir"' 0
trap 'exit 1' 1 2 15

# Verify the minimum native dependency before downloading or installing.
printf '#include <zlib.h>\nint main(void) { return zlibVersion() == 0; }\n' >"$work_dir/probe.c"
"$cc" "$work_dir/probe.c" -lz -o "$work_dir/probe" 2>"$work_dir/probe.log" ||
	fail 'cannot compile with zlib; install a C toolchain and zlib development files (see README)'

if [ -n "$source_dir" ]; then
	source_dir=$(cd "$source_dir" && pwd -P) || fail 'invalid --source directory'
else
	url="https://codeload.github.com/jfdiazbus/gitten/tar.gz/$ref"
	printf 'Downloading gitten (%s)...\n' "$ref"
	if command -v curl >/dev/null 2>&1; then
		curl -fL --retry 3 "$url" -o "$work_dir/source.tar.gz"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$work_dir/source.tar.gz" "$url"
	else
		fail 'install curl or wget to download the source'
	fi
	mkdir "$work_dir/source"
	tar -xzf "$work_dir/source.tar.gz" --strip-components=1 -C "$work_dir/source"
	source_dir=$work_dir/source
fi
[ -f "$source_dir/Makefile" ] && [ -f "$source_dir/builtin/hidden.c" ] ||
	fail 'source directory does not contain gitten'

# These disable optional GUI, translation, web UI, and Rust build dependencies.
set -- "prefix=$prefix" "CC=$cc" CFLAGS=-O2 NO_RUST=YesPlease NO_GETTEXT=YesPlease \
	NO_TCLTK=YesPlease NO_GITWEB=YesPlease NO_OPENSSL=YesPlease
printf '#include <curl/curl.h>\nint main(void) { return curl_global_init(CURL_GLOBAL_DEFAULT); }\n' >"$work_dir/probe.c"
if ! "$cc" "$work_dir/probe.c" -lcurl -o "$work_dir/probe" 2>"$work_dir/probe.log"; then
	set -- "$@" NO_CURL=YesPlease
	printf '%s\n' 'curl development files unavailable: HTTP(S) remotes will be disabled; local and SSH remotes remain available.'
fi
printf '#include <expat.h>\nint main(void) { XML_ParserFree(XML_ParserCreate(0)); return 0; }\n' >"$work_dir/probe.c"
if ! "$cc" "$work_dir/probe.c" -lexpat -o "$work_dir/probe" 2>"$work_dir/probe.log"; then
	set -- "$@" NO_EXPAT=YesPlease
fi

# Resolve installation paths before compiling them into the executable.
mkdir -p "$prefix" "$bin_dir"
prefix=$(cd "$prefix" && pwd -P)
bin_dir=$(cd "$bin_dir" && pwd -P)
[ ! -d "$bin_dir/gitten" ] || fail "$bin_dir/gitten is a directory"
# The final prefix overrides the original path, which may have been relative.
"$make_command" -C "$source_dir" -j"$jobs" "$@" "prefix=$prefix" all
"$make_command" -C "$source_dir" "$@" "prefix=$prefix" INSTALL_STRIP=-s install
if [ "$bin_dir" != "$prefix/bin" ]; then
	ln -sf "$prefix/bin/gitten" "$bin_dir/gitten"
fi
"$bin_dir/gitten" --version
printf '\nInstalled: %s/gitten\n' "$bin_dir"
case ":$PATH:" in
	*:"$bin_dir":*) ;;
	*) printf 'Add %s to PATH to run gitten from any directory.\n' "$bin_dir" ;;
esac
printf '%s\n' 'Your system git is unchanged. Use gitten for .githidden support.'
