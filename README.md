# gitten

Git with repository-root `.githidden` rules. This repository contains the full
Git source at its root, plus native hidden-file support. Git commands,
repository formats, and remote protocols are preserved.

## Build and run

Install the build dependencies described in [INSTALL](INSTALL), then run from
this directory:

```sh
make -j8 all
./gitten --version
./gitten hidden apply --dry-run
```

**Use `./gitten`, not your system `git`.** Building does not replace
`/usr/bin/git`, and stock Git does not read `.githidden`.

If curl, expat, or gettext development dependencies are unavailable:

```sh
make -j8 NO_CURL=YesPlease NO_EXPAT=YesPlease NO_GETTEXT=YesPlease all
```

This fallback build supports local and SSH remotes but omits HTTP(S) transport.
To install without replacing the system Git, use a dedicated prefix and the
same build flags for both commands:

```sh
make -j8 prefix="$HOME/.local/opt/gitten" all
make prefix="$HOME/.local/opt/gitten" install
export PATH="$HOME/.local/opt/gitten/bin:$PATH"
gitten hidden apply --dry-run
```

The prefix contains both `gitten` and this fork's `git` and helper programs.

## Hide local files

Create `.githidden` in your repository root:

```gitignore
# Local files that should stay out of future commits
.env
*.secret
cache/
/root-only.txt
file with spaces
!public.secret
```

Patterns use [Git ignore syntax](Documentation/gitignore.adoc). Nested
`.githidden` files are not read. Directory exclusions also exclude their
contents; re-include the parent before re-including a child. `.gitignore`
continues to work independently: exceptions in either file cannot override
exclusions in the other.

```sh
./gitten status
./gitten add .
./gitten ls-files --others --exclude-standard
./gitten check-ignore -v .env
```

Matching untracked files disappear from normal status and staging.
`./gitten add -f .env` deliberately overrides exclusions. Track `.githidden`
itself to share rules, ensuring your patterns do not exclude it.

Already tracked files keep normal Git behavior until explicitly untracked:

```sh
./gitten hidden apply --dry-run
./gitten hidden apply
./gitten commit -m "Stop tracking local files"
```

`hidden apply` checks the entire repository, stages matching removals, and
preserves working files. It rejects conflicts or staged content that would
be lost. Dry runs perform the same checks without writing the index.
Previously committed files remain in history; this feature does not erase
secrets from old commits.

See [git-hidden](Documentation/git-hidden.adoc) for command details.

## Test and clean

After building:

```sh
make -C t t1099-githidden.sh
make clean
```

`make clean` removes generated programs and build artifacts. Rebuild before
running `./gitten` again. Copied repository metadata such as `.giti/` is not
part of the project and must never be committed.

Git-derived source is licensed under GPLv2; see [COPYING](COPYING) and the
upstream licensing notices.
