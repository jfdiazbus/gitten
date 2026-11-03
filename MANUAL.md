# gitten command manual

gitten is Git with additional rules for local files in a repository-root
`.githidden`. Use `gitten` in place of `git`; existing Git repositories and
remote protocols work without conversion. Stock Git does not read these rules.

## Install and update

```sh
curl -fsSL https://raw.githubusercontent.com/jfdiazbus/gitten/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
gitten --version
```

The installer builds from source. See [README.md](https://github.com/jfdiazbus/gitten/blob/main/README.md#download-and-install)
for required dependencies, custom paths, and HTTP(S) support. Re-run the installer
to update. It installs the manual at
`~/.local/opt/gitten/share/doc/gitten/MANUAL.md` when using the default prefix.
Your system Git remains available as before.

## Common commands

```sh
gitten init my-project             # Create a repository
gitten clone <url>                # Download an existing repository
gitten status                     # Inspect staged and working changes
gitten add <file>                  # Stage a file
gitten add .                       # Stage ordinary project changes
gitten diff                        # Inspect unstaged changes
gitten diff --cached               # Inspect the next commit
gitten commit -m "Describe change" # Record staged changes
gitten log --oneline               # Inspect history
gitten switch -c feature           # Create and switch to a branch
gitten pull                       # Fetch and integrate remote changes
gitten push                       # Upload local commits
```

For standard Git command options, use `gitten <command> -h` or
`gitten help <command>`. Full help requires installed Git manual pages;
short command help works without a man-page viewer.

## Write hidden-file rules

Create `.githidden` at the repository root, for example:

```gitignore
# Credentials and local output
.env
*.secret
cache/
/root-only.txt
!public.secret
```

- A bare name matches that name at any directory depth.
- `git*` matches names beginning with `git`, including directories.
- A leading `/` anchors the pattern to the repository root.
- A trailing `/` matches directories and their contents.
- `*`, `?`, and `**` use Git ignore wildcard rules.
- `#` begins a comment; `!` makes an exception to preceding hidden rules.
- A child cannot be re-included while its parent directory remains excluded.

Only the root `.githidden` is read, even when commands run from a subdirectory.
See [Git ignore syntax](https://github.com/jfdiazbus/gitten/blob/main/Documentation/gitignore.adoc) for escaping and matching
rules. Commit `.githidden` to share its rules; ensure the patterns do not exclude
that file itself.

Matching untracked files are omitted from normal status, staging, and discovery
with standard exclusions:

```sh
gitten status
gitten add .
gitten ls-files --others --exclude-standard
gitten check-ignore -v --no-index <path>
```

`.gitignore` works independently. An exception in one file cannot undo an
exclusion in the other. A deliberate `gitten add -f <path>` overrides exclusions.
The project's own `.githidden` also lists optional CI, GUI, web, translation,
release-note, and formatting files not required by the command-line installer.
Those optional files and generated build outputs are excluded from the tracked
source tree. Applying hidden rules preserves any existing local copies; a fresh
clone builds the command-line tools without them.

## Stop tracking existing files

Adding a rule does not automatically untrack files already in the index.
Preview and explicitly apply the removals:

```sh
gitten hidden apply --dry-run
gitten hidden apply
gitten diff --cached
gitten commit -m "Stop tracking local files"
```

Both commands examine the entire repository. `--dry-run` lists matching tracked
paths without writing the index. Applying stages their removal but leaves local
copies untouched. It rejects conflicted paths and staged content that differs
from both HEAD and the local file; all paths are checked before updating the
index. Resolve those conflicts or preserve the staged content before retrying.
Applying again after untracking has no effect.

## Stop hiding files

```sh
gitten stop
```

This disables `.githidden` rules for the current local repository by setting
`gitten.hidden=false` in its Git configuration. The setting persists across
commands and also applies to linked worktrees sharing the repository config.
The rules file, local files, commits, and index are preserved. Untracked files
excluded only by `.githidden` become visible and eligible for normal staging.
Rules from `.gitignore` and other standard ignore sources still apply.
`gitten hidden apply` has no effect while hidden rules are disabled.

Re-enable hidden rules:

```sh
gitten config --local gitten.hidden true
```

Or enable them for one command without changing the saved setting:

```sh
gitten -c gitten.hidden=true status
```

Hidden rules are enabled by default. The local stop setting is not shared by
push or clone. Stopping does not re-track files previously removed with
`hidden apply`, undo staged removals, or restore files from older commits.
Review the index before adding files again; `gitten add <path>` can track local
copies once normal ignore rules permit them.

## History and compatibility

Hidden rules do not erase existing commits or remove secrets from history.
Any previously committed file remains accessible in older commits. Other users
running stock Git do not enforce `.githidden`, and `gitten stop` cannot override
ordinary `.gitignore` rules. Always inspect `gitten diff --cached` before a
commit when changing hidden-file behavior.
