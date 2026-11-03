/* Keep root .githidden matches locally while explicitly untracking them. */
#include "builtin.h"
#include "config.h"
#include "dir.h"
#include "gettext.h"
#include "lockfile.h"
#include "object-name.h"
#include "parse-options.h"
#include "quote.h"
#include "read-cache.h"
#include "repository.h"
#include "sparse-index.h"
#include "string-list.h"
#include "tree-walk.h"

static const char * const hidden_usage[] = {
	N_("git hidden apply [--dry-run]"),
	NULL
};

int cmd_hidden(int argc, const char **argv, const char *prefix,
	       struct repository *repo)
{
	int dry_run = 0, errors = 0, have_head;
	struct option options[] = {
		OPT__DRY_RUN(&dry_run, N_("list removals without changing the index")),
		OPT_END()
	};
	struct dir_struct hidden = DIR_INIT;
	struct lock_file lock = LOCK_INIT;
	struct string_list paths = STRING_LIST_INIT_DUP;
	struct object_id head;

	if (argc < 2 || strcmp(argv[1], "apply"))
		usage_with_options(hidden_usage, options);
	argc = parse_options(argc - 1, argv + 1, prefix, options,
			     hidden_usage, 0);
	if (argc)
		usage_with_options(hidden_usage, options);

	repo_config(repo, git_default_config, NULL);
	repo_hold_locked_index(repo, &lock, LOCK_DIE_ON_ERROR);
	if (repo_read_index(repo) < 0)
		die(_("index file corrupt"));
	ensure_full_index(repo->index);
	setup_hidden_excludes(&hidden);
	have_head = !repo_get_oid_tree(repo, "HEAD", &head);

	for (size_t i = 0; i < repo->index->cache_nr; i++) {
		const struct cache_entry *ce = repo->index->cache[i];
		int dtype = S_ISGITLINK(ce->ce_mode) ? DT_DIR : DT_UNKNOWN;
		struct object_id oid;
		unsigned short mode;
		struct stat st;

		if (!is_excluded(&hidden, repo->index, ce->name, &dtype))
			continue;
		if (ce_stage(ce)) {
			errors |= error(_("cannot hide conflicted path '%s'"), ce->name);
			continue;
		}
		/* Index content must survive in HEAD or in the working file. */
		if (!(have_head &&
		      !get_tree_entry(repo, &head, ce->name, &oid, &mode) &&
		      mode == ce->ce_mode && oideq(&oid, &ce->oid)) &&
		    (S_ISGITLINK(ce->ce_mode) || ce_intent_to_add(ce) ||
		     lstat(ce->name, &st) ||
		     ie_modified(repo->index, ce, &st,
				 CE_MATCH_IGNORE_VALID | CE_MATCH_IGNORE_SKIP_WORKTREE |
				 CE_MATCH_IGNORE_FSMONITOR))) {
			errors |= error(_("cannot hide '%s': staged content differs from both HEAD and the working file"), ce->name);
			continue;
		}
		string_list_append(&paths, ce->name);
	}

	if (!errors) {
		for (size_t i = 0; i < paths.nr; i++) {
			if (!dry_run && remove_file_from_index(repo->index, paths.items[i].string))
				die(_("cannot remove '%s' from the index"), paths.items[i].string);
			write_name_quoted(paths.items[i].string, stdout, '\n');
		}
		if (!dry_run && write_locked_index(repo->index, &lock,
						 COMMIT_LOCK | SKIP_IF_UNCHANGED))
			die(_("unable to write index"));
	}
	rollback_lock_file(&lock);
	string_list_clear(&paths, 0);
	dir_clear(&hidden);
	return errors ? 1 : 0;
}

static const char * const stop_usage[] = {
	N_("git stop"),
	NULL
};

int cmd_stop(int argc, const char **argv, const char *prefix,
	     struct repository *repo)
{
	struct option options[] = { OPT_END() };

	argc = parse_options(argc, argv, prefix, options, stop_usage, 0);
	if (argc)
		usage_with_options(stop_usage, options);
	if (repo_config_set_gently(repo, "gitten.hidden", "false"))
		return error(_("unable to disable .githidden rules"));
	puts(_(".githidden rules are disabled for this repository."));
	puts(_("Re-enable with: gitten config --local gitten.hidden true"));
	return 0;
}
