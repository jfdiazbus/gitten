#!/bin/sh

test_description='root .githidden exclusions and safe explicit untracking'
. ./test-lib.sh

test_expect_success 'patterns, root anchoring, negation, and independent ignore lists' '
	test_create_repo patterns &&
	(
		cd patterns &&
		mkdir -p cache sub &&
		cat >.githidden <<-\EOF_RULES &&
		# comment
		*.secret
		!public.secret
		cache/
		/root-only
		file with spaces
		!ordinary
		EOF_RULES
		printf "ordinary\n!private.secret\n" >.gitignore &&
		touch private.secret public.secret ordinary root-only "file with spaces" cache/data sub/root-only &&
		echo nested >sub/.githidden &&
		touch sub/nested &&
		git ls-files --others --exclude-standard >actual &&
		test_grep public.secret actual &&
		test_grep sub/root-only actual &&
		test_grep sub/nested actual &&
		test_grep ! private.secret actual &&
		test_grep ! ordinary actual &&
		test_grep ! "^root-only$" actual &&
		test_grep ! "file with spaces" actual &&
		test_grep ! cache/data actual &&
		test_must_fail git add private.secret 2>err &&
		test_grep .githidden err &&
		git add -f private.secret &&
		git ls-files --error-unmatch private.secret &&
		git add .githidden &&
		git ls-files --error-unmatch .githidden &&
		(cd sub && test_must_fail git add ../root-only)
	)
'

test_expect_success 'directory exclusions and check-ignore source' '
	(
		cd patterns &&
		git check-ignore -v cache/data >actual &&
		test_grep ".githidden:4:cache/" actual &&
		git status --short --untracked-files=all >actual &&
		test_grep ! cache/data actual &&
		test_must_fail git add cache/data
	)
'

test_expect_success 'tracked paths remain normal until apply, dry-run preserves index' '
	test_create_repo tracked &&
	(
		cd tracked &&
		mkdir sub &&
		echo original >sub/secret &&
		git add sub/secret &&
		git commit -m initial &&
		echo sub/secret >.githidden &&
		echo local >sub/secret &&
		git status --short >actual &&
		test_grep " M sub/secret" actual &&
		cp .git/index before &&
		(cd sub && git hidden apply --dry-run) >actual &&
		echo sub/secret >expect &&
		test_cmp expect actual &&
		test_cmp before .git/index &&
		git hidden apply >actual &&
		test_cmp expect actual &&
		test_path_is_file sub/secret &&
		test_must_fail git ls-files --error-unmatch sub/secret &&
		git commit -m hidden &&
		git ls-tree -r --name-only HEAD >actual &&
		test_must_be_empty actual &&
		git hidden apply >actual &&
		test_must_be_empty actual
	)
'

test_expect_success 'refuse losing staged-only content atomically, including dry-run' '
	test_create_repo staged &&
	(
		cd staged &&
		echo first >a && echo first >b &&
		git add a b && git commit -m initial &&
		echo staged >b && git add b &&
		echo working >b &&
		printf "a\nb\n" >.githidden &&
		cp .git/index before &&
		test_must_fail git hidden apply &&
		test_cmp before .git/index &&
		test_must_fail git hidden apply --dry-run &&
		test_cmp before .git/index
	)
'

test_expect_success 'new staged content may be removed when preserved in working file' '
	test_create_repo unborn &&
	(
		cd unborn &&
		echo secret >secret && git add secret &&
		echo secret >.githidden &&
		git hidden apply &&
		test_path_is_file secret &&
		git ls-files >actual && test_must_be_empty actual
	)
'

test_expect_success 'conflicted matching paths are rejected without changing index' '
	test_create_repo conflicted &&
	(
		cd conflicted &&
		echo content >secret &&
		oid=$(git hash-object -w secret) &&
		printf "100644 %s 1\tsecret\n100644 %s 2\tsecret\n100644 %s 3\tsecret\n" "$oid" "$oid" "$oid" |
		git update-index --index-info &&
		echo secret >.githidden &&
		cp .git/index before &&
		test_must_fail git hidden apply &&
		test_cmp before .git/index
	)
'

test_expect_success 'cache sees creation, edits, and deletion of hidden rules' '
	test_create_repo cached &&
	(
		cd cached &&
		git config core.untrackedCache true &&
		mkdir sub && touch sub/a sub/b &&
		git status --porcelain -uall >actual &&
		echo sub/a >.githidden &&
		git status --porcelain -uall >actual &&
		test_grep ! sub/a actual && test_grep sub/b actual &&
		git status --porcelain -uall >actual &&
		echo sub/b >.githidden &&
		git status --porcelain -uall >actual &&
		test_grep sub/a actual && test_grep ! sub/b actual &&
		rm .githidden &&
		git status --porcelain -uall >actual &&
		test_grep sub/a actual && test_grep sub/b actual
	)
'

test_expect_success 'gitten entry point supports local clone, commit, and push' '
	"$GIT_BUILD_DIR/gitten" init --bare remote.git &&
	"$GIT_BUILD_DIR/gitten" clone remote.git client &&
	(
		cd client &&
		echo secret >.githidden &&
		echo local >secret && echo public >public &&
		"$GIT_BUILD_DIR/gitten" add . &&
		"$GIT_BUILD_DIR/gitten" commit -m public &&
		"$GIT_BUILD_DIR/gitten" push origin HEAD &&
		git ls-tree -r --name-only HEAD >actual &&
		test_grep ! "^secret$" actual
	) &&
	git --git-dir=remote.git ls-tree -r --name-only HEAD >actual &&
	test_grep ! "^secret$" actual
'

test_expect_success 'directory rules untrack descendants and respect parent reinclusion' '
	test_create_repo directories &&
	(
		cd directories &&
		mkdir -p cache nested &&
		echo keep >cache/keep && echo secret >cache/drop &&
		echo public >nested/public &&
		git add . && git commit -m initial &&
		printf "cache/\n!cache/\ncache/*\n!cache/keep\n" >.githidden &&
		git hidden apply >actual &&
		echo cache/drop >expect && test_cmp expect actual &&
		git ls-files --error-unmatch cache/keep nested/public &&
		test_path_is_file cache/drop
	)
'

test_expect_success 'staged-only content remains protected with assume-unchanged' '
	(
		cd staged &&
		git update-index --assume-unchanged b &&
		cp .git/index before &&
		test_must_fail git hidden apply &&
		test_cmp before .git/index
	)
'

test_expect_success 'missing working files can be untracked when HEAD preserves content' '
	test_create_repo missing &&
	(
		cd missing &&
		echo original >secret && git add secret && git commit -m initial &&
		rm secret && echo secret >.githidden &&
		git hidden apply &&
		git ls-files >actual && test_must_be_empty actual
	)
'

test_expect_success SYMLINKS 'hidden rules cannot be read through a symlink' '
	test_create_repo symlink &&
	(
		cd symlink &&
		echo secret >rules && ln -s rules .githidden &&
		test_must_fail git status
	)
'

test_expect_success 'stop preserves rules and index, persists, and respects standard ignores' '
	test_create_repo stopped &&
	(
		cd stopped &&
		mkdir sub && echo tracked >tracked &&
		git add tracked && git commit -m initial &&
		printf "secret\nignored\ntracked\n" >.githidden &&
		echo ignored >.gitignore && touch secret ignored &&
		git config core.untrackedCache true &&
		git status --porcelain -uall >actual &&
		git status --porcelain -uall >actual &&
		test_grep ! secret actual &&
		cp .git/index before && cp .githidden rules-before &&
		(cd sub && "$GIT_BUILD_DIR/gitten" stop) &&
		test_cmp before .git/index && test_cmp rules-before .githidden &&
		test "$(git config --local --get gitten.hidden)" = false &&
		git hidden apply >applied && test_must_be_empty applied &&
		test_cmp before .git/index &&
		git status --porcelain -uall >actual &&
		test_grep secret actual && test_grep ! ignored actual &&
		git status --porcelain -uall >actual &&
		git add secret && git ls-files --error-unmatch secret &&
		git stop && test "$(git config --local --get gitten.hidden)" = false
	)
'

test_expect_success 're-enabling rules invalidates the untracked cache' '
	(
		cd stopped &&
		echo local >another && echo another >>.githidden &&
		git status --porcelain -uall >actual &&
		test_grep another actual &&
		git status --porcelain -uall >actual &&
		git config --local gitten.hidden true &&
		git status --porcelain -uall >actual &&
		test_grep ! another actual &&
		git check-ignore another &&
		git ls-files --error-unmatch tracked
	)
'

test_expect_success 'one-command override does not change saved stop setting' '
	(
		cd stopped &&
		git stop &&
		git -c gitten.hidden=true status --porcelain -uall >actual &&
		test_grep ! another actual &&
		test "$(git config --local --get gitten.hidden)" = false &&
		git status --porcelain -uall >actual && test_grep another actual
	)
'

test_expect_success 'unexpected stop arguments do not change configuration' '
	(
		cd stopped &&
		git config --local gitten.hidden true &&
		test_must_fail git stop unexpected &&
		test "$(git config --local --get gitten.hidden)" = true
	)
'

test_expect_success SYMLINKS 'stop bypasses an unreadable hidden rule source' '
	(
		cd symlink &&
		git stop && git status --porcelain >actual &&
		git config --local gitten.hidden true &&
		test_must_fail git status
	)
'

test_done
