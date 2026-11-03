#!/usr/bin/env bash
# Tests for scripts/check_command_blocks.py.
#
# Every failing shape the check is supposed to catch is built here in a scratch
# tree and asserted to exit 1 naming the file, the line and the rule; the
# delivered tree itself is asserted to exit 0. Shell rather than pytest so it
# runs with nothing installed: bash and python3 are all this needs.
#
#   bash scripts/test_command_blocks.sh
#
# Output is TAP-ish: one line per leaf test. Exit 0 when every test passes.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out.txt"

COUNT=0
FAILED=0

ok() {  # ok <leaf test name>
    COUNT=$((COUNT + 1))
    printf 'ok %d - %s\n' "$COUNT" "$1"
}

not_ok() {  # not_ok <leaf test name> <why>
    COUNT=$((COUNT + 1))
    FAILED=$((FAILED + 1))
    printf 'not ok %d - %s\n' "$COUNT" "$1"
    printf '  ---\n  reason: %s\n  ---\n' "$2"
}

run_check() {  # run_check <root> [option...]
    local root="$1"
    shift
    python3 -B "$REPO/scripts/check_command_blocks.py" --root "$root" "$@" > "$OUT" 2>&1
}

new_tree() {  # new_tree <name> -> path to an empty scratch tree
    mkdir -p "$TMP/$1"
    printf '%s' "$TMP/$1"
}

md() {  # md <tree> <path> < content: writes the file, making its directory
    mkdir -p "$(dirname "$1/$2")"
    cat > "$1/$2"
}

expect_fail() {  # expect_fail <leaf name> <root> <file:line>...: exit 1, [unmade] at each
    local name="$1" root="$2" rc where
    shift 2
    run_check "$root"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        not_ok "$name" "expected exit 1, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
        return
    fi
    for where in "$@"; do
        if ! grep -qF -- "- $where [unmade]" "$OUT"; then
            not_ok "$name" "exit 1 but '$where [unmade]' not reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
            return
        fi
    done
    ok "$name"
}

expect_pass() {  # expect_pass <leaf name> <root>
    local name="$1" root="$2" rc
    run_check "$root"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 0, got $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
    fi
}

expect_unreported() {  # expect_unreported <leaf name> <file:line>: the last run reported nothing there
    if grep -qF -- "- $2 [" "$OUT"; then
        not_ok "$1" "'$2' reported: $(head -c 400 "$OUT" | tr '\n' ' ')"
    else
        ok "$1"
    fi
}

# --- the delivered tree -----------------------------------------------------

run_check "$REPO"
rc=$?
checked="$(grep -oE '[0-9]+ cd command' "$OUT" | grep -oE '^[0-9]+')"
if [ "$rc" -eq 0 ] && [ "${checked:-0}" -ge 1 ]; then
    ok "the repository's own Markdown passes, with at least one cd checked"
else
    not_ok "the repository's own Markdown passes, with at least one cd checked" \
        "exit $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- the block of issue 150 -------------------------------------------------

T="$(new_tree no-clone)"
md "$T" docs/use-cases.md <<'EOF'
### Your identity team asks where ATX sits beside what it runs

```sh
cd atx-conformance/verifiers/go
go run . ../../fixtures/cross-issuer-key.json
```
EOF
expect_fail "a block that changes into the suite without cloning it fails at its cd" \
    "$T" "docs/use-cases.md:4"

T="$(new_tree clone-first)"
md "$T" docs/use-cases.md <<'EOF'
### Your identity team asks where ATX sits beside what it runs

```sh
git clone https://github.com/opena2a-standards/atx-conformance
cd atx-conformance/verifiers/go
go run . ../../fixtures/cross-issuer-key.json
```
EOF
expect_pass "the same block with the clone step first passes" "$T"

T="$(new_tree earlier-block)"
md "$T" docs/use-cases.md <<'EOF'
```sh
git clone https://github.com/opena2a-standards/atx-conformance
cd atx-conformance/verifiers/go
go run . ../../fixtures/wrong-issuer.json
```

```sh
cd atx-conformance/verifiers/go
go run . ../../fixtures/cross-issuer-key.json
```
EOF
expect_fail "a block does not inherit the clone of the block before it" "$T" "docs/use-cases.md:8"
expect_unreported "the block that clones the suite itself is not reported" "docs/use-cases.md:3"

# --- git clone --------------------------------------------------------------

T="$(new_tree one-line)"
md "$T" README.md <<'EOF'
```sh
git clone https://github.com/opena2a-standards/atx-conformance && cd atx-conformance/verifiers/go
```
EOF
expect_pass "a clone and a cd joined by && on one line pass" "$T"

T="$(new_tree named-dir)"
md "$T" README.md <<'EOF'
```sh
git clone https://github.com/opena2a-standards/atx-conformance suite
cd suite/verifiers/go
```
EOF
expect_pass "a clone into a named directory makes that directory" "$T"

T="$(new_tree named-dir-other)"
md "$T" README.md <<'EOF'
```sh
git clone https://github.com/opena2a-standards/atx-conformance suite
cd atx-conformance
```
EOF
expect_fail "a clone into a named directory does not make the repository's name" "$T" "README.md:3"

T="$(new_tree url-forms)"
md "$T" README.md <<'EOF'
```sh
git clone https://example.org/org/one.git
git clone https://example.org/org/two/
git clone git@example.org:org/three.git
git clone /srv/repos/four/.git
cd one
cd ../two
cd ../three
cd ../four
```
EOF
expect_pass "a URL's .git suffix, trailing slash, scp form and /.git end give the repository's name" "$T"

T="$(new_tree clone-options)"
md "$T" README.md <<'EOF'
```sh
git clone --depth 1 -b main https://github.com/opena2a-standards/atx-conformance
cd atx-conformance
```

```sh
git clone --depth=1 --single-branch https://github.com/opena2a-standards/atx-conformance
cd atx-conformance
```
EOF
expect_pass "git clone options, and the values of those that take one, are skipped" "$T"

T="$(new_tree other-maker)"
md "$T" README.md <<'EOF'
```sh
tar -xzf atx-conformance.tar.gz
cd atx-conformance
```
EOF
expect_fail "a directory another command makes, such as an unpacked archive, does not count" \
    "$T" "README.md:3"

# --- mkdir ------------------------------------------------------------------

T="$(new_tree mkdir)"
md "$T" README.md <<'EOF'
```sh
mkdir -p work/out
cd work
cd out
cd ../..
mkdir demo && cd demo
```
EOF
expect_pass "mkdir makes each directory it names and those above it" "$T"

T="$(new_tree mkdir-mode)"
md "$T" README.md <<'EOF'
```sh
mkdir -m 700 private
cd 700
```

```sh
mkdir -m 700 private
cd private
```
EOF
expect_fail "the value of mkdir -m is not a directory it makes" "$T" "README.md:3"
expect_unreported "the directory mkdir -m names is made" "README.md:8"

# --- cd ---------------------------------------------------------------------

T="$(new_tree climb)"
md "$T" README.md <<'EOF'
```sh
git clone https://github.com/opena2a-standards/atx-conformance
cd atx-conformance/verifiers/go
cd ../python
cd ../../..
cd ./atx-conformance
cd .
```
EOF
expect_pass "a cd that climbs within the clone or back to the start passes" "$T"

T="$(new_tree unknown)"
md "$T" README.md <<'EOF'
```sh
cd /tmp
cd anywhere
```

```sh
cd ~/src
cd anywhere
```

```sh
cd "$HOME"
cd anywhere
```

```sh
cd `git rev-parse --show-toplevel`
cd anywhere
```

```sh
cd -
cd anywhere
```

```sh
cd
cd anywhere
```

```sh
cd ..
cd anywhere
```

```sh
cd src-*
cd anywhere
```

```sh
cd src-?
cd anywhere
```

```sh
cd src-[ab]
cd anywhere
```

```sh
pushd /tmp
cd anywhere
```

```sh
popd
cd anywhere
```
EOF
expect_pass "after a cd or pushd whose target the block does not decide, later cd commands are not checked" \
    "$T"

T="$(new_tree reported-once)"
md "$T" README.md <<'EOF'
```sh
cd nowhere
cd also-nowhere
```
EOF
expect_fail "a cd into a directory the block did not make fails" "$T" "README.md:2"
expect_unreported "a cd after a reported one is not checked" "README.md:3"

T="$(new_tree cd-option)"
md "$T" README.md <<'EOF'
```sh
cd -P nowhere
```
EOF
expect_fail "options of cd are skipped to reach its operand" "$T" "README.md:2"

# --- which blocks are read --------------------------------------------------

T="$(new_tree not-shell)"
md "$T" README.md <<'EOF'
```text
cd nowhere
```

```
cd nowhere
```

```console
$ cd nowhere
```

```python
cd nowhere
```
EOF
expect_pass "a block whose info string names no shell is not read" "$T"

n=0
for info in bash shell zsh SH 'sh title=demo'; do
    n=$((n + 1))
    T="$(new_tree "info-$n")"
    printf '```%s\ncd nowhere\n```\n' "$info" | md "$T" README.md
    expect_fail "a block whose info string starts with '$info' is read" "$T" "README.md:2"
done

T="$(new_tree tilde)"
md "$T" README.md <<'EOF'
~~~sh
```
cd nowhere
~~~
EOF
expect_fail "a tilde fence opens a block that a backtick fence does not close" "$T" "README.md:3"

T="$(new_tree long-fence)"
md "$T" README.md <<'EOF'
````sh
```
cd nowhere
````
EOF
expect_fail "a block closes only on a fence at least as long as the one that opened it" \
    "$T" "README.md:3"

T="$(new_tree fence-text)"
md "$T" README.md <<'EOF'
```sh
``` not a closing fence
cd nowhere
```
EOF
expect_fail "a fence with text after it does not close a block" "$T" "README.md:3"

T="$(new_tree indented)"
md "$T" README.md <<'EOF'
Intro.

    ```sh
    cd nowhere
    ```
EOF
expect_pass "a fence indented four spaces opens no block" "$T"

T="$(new_tree unclosed)"
md "$T" README.md <<'EOF'
Intro.

```sh
cd nowhere
EOF
expect_fail "a block with no closing fence runs to the end of the file" "$T" "README.md:4"

# --- how a line is read -----------------------------------------------------

T="$(new_tree comments)"
md "$T" README.md <<'EOF'
```sh
# cd nowhere
git clone https://github.com/opena2a-standards/atx-conformance # the suite
cd atx-conformance
```
EOF
expect_pass "a comment is not a command" "$T"

T="$(new_tree comment-in-word)"
md "$T" README.md <<'EOF'
```sh
git clone https://github.com/opena2a-standards/atx-conformance
cd atx-conformance#verifiers
```
EOF
expect_pass "an unquoted # starts a comment inside a word too" "$T"

T="$(new_tree quoted-operator)"
md "$T" README.md <<'EOF'
```sh
echo ";" cd nowhere
echo "a;b" cd elsewhere
```
EOF
expect_fail "a quoted word made only of operator characters ends a command" "$T" "README.md:2"
expect_unreported "a quoted word that holds other characters is one word" "README.md:3"

T="$(new_tree continued-clone)"
md "$T" README.md <<'EOF'
```sh
git clone \
  https://github.com/opena2a-standards/atx-conformance
cd atx-conformance
```
EOF
expect_pass "a line that ends in a backslash is read with the next" "$T"

T="$(new_tree continued-cd)"
md "$T" README.md <<'EOF'
```sh
cd \
  nowhere
```
EOF
expect_fail "a continued cd is reported at the line it starts on" "$T" "README.md:2"

T="$(new_tree escaped-backslash)"
md "$T" README.md <<'EOF'
```sh
echo done \\
cd nowhere
```
EOF
expect_fail "a line that ends in two backslashes does not continue" "$T" "README.md:3"

T="$(new_tree open-quote)"
md "$T" README.md <<'EOF'
```sh
echo "first
second"; cd nowhere
```
EOF
expect_fail "a quote left open is read with the next line, reported where it starts" \
    "$T" "README.md:2"

T="$(new_tree heredoc)"
md "$T" README.md <<'EOF'
```sh
cat > notes.txt <<'NOTE'
cd nowhere
it's a note
NOTE
cd elsewhere
```
EOF
expect_fail "reading resumes after a here-document's delimiter" "$T" "README.md:6"
expect_unreported "a here-document's lines are not read as commands" "README.md:3"

T="$(new_tree heredoc-tabs)"
printf '```sh\ncat <<-NOTE\n\tcd nowhere\n\tNOTE\ncd elsewhere\n```\n' | md "$T" README.md
expect_fail "a <<- here-document ends at its tab-indented delimiter" "$T" "README.md:5"
expect_unreported "the lines of a <<- here-document are not read as commands" "README.md:3"

T="$(new_tree subshell)"
md "$T" README.md <<'EOF'
```sh
git clone https://github.com/opena2a-standards/atx-conformance
(cd atx-conformance/verifiers/go && go run . ../../fixtures)
cd verifiers
```
EOF
expect_fail "a cd inside parentheses does not hold after the closing one" "$T" "README.md:4"

T="$(new_tree subshell-inside)"
md "$T" README.md <<'EOF'
```sh
git clone https://github.com/opena2a-standards/atx-conformance
(cd atx-conformance && cd verifiers/go)
```
EOF
expect_pass "a cd inside parentheses holds until the closing one" "$T"

T="$(new_tree reserved)"
md "$T" README.md <<'EOF'
```sh
if true; then cd nowhere; fi
```

```sh
{ cd nowhere; }
```

```sh
GOFLAGS=-mod=mod cd nowhere
```
EOF
expect_fail "reserved words and variable assignments before a cd are passed over" \
    "$T" "README.md:2" "README.md:6" "README.md:10"

# --- which files are read ---------------------------------------------------

T="$(new_tree history)"
printf 'Clean.\n' | md "$T" README.md
md "$T" CHANGELOG.md <<'EOF'
- The block read:

  ```sh
  cd atx-conformance/verifiers/go
  ```
EOF
md "$T" errata/ATX-E-0001.md <<'EOF'
```sh
cd atx-conformance/verifiers/go
```
EOF
expect_pass "CHANGELOG.md and errata, which quote earlier text, are not checked" "$T"

T="$(new_tree skipped-dirs)"
printf 'Clean.\n' | md "$T" README.md
printf '```sh\ncd nowhere\n```\n' | md "$T" .suite/README.md
printf '```sh\ncd nowhere\n```\n' | md "$T" node_modules/pkg/README.md
expect_pass "hidden directories such as a suite checkout, and node_modules, are not checked" "$T"

T="$(new_tree encoding)"
printf 'Clean.\n' | md "$T" README.md
printf 'caf\351\n' | md "$T" docs/latin1.md
run_check "$T"
if [ $? -eq 1 ] && grep -qF -- "- docs/latin1.md [encoding]" "$OUT"; then
    ok "a file that is not UTF-8 text fails as [encoding]"
else
    not_ok "a file that is not UTF-8 text fails as [encoding]" "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- vacuous pass and usage -------------------------------------------------

T="$(new_tree empty)"
run_check "$T"
if [ $? -eq 1 ] && grep -q "refusing to pass vacuously" "$OUT"; then
    ok "a tree with no Markdown files exits 1 instead of passing vacuously"
else
    not_ok "a tree with no Markdown files exits 1 instead of passing vacuously" \
        "$(head -c 400 "$OUT" | tr '\n' ' ')"
fi

run_check "$REPO" --no-such-option
rc=$?
if [ "$rc" -eq 2 ]; then
    ok "an unknown option is a usage error, exit 2"
else
    not_ok "an unknown option is a usage error, exit 2" "exit $rc: $(head -c 400 "$OUT" | tr '\n' ' ')"
fi

# --- summary ----------------------------------------------------------------

printf '1..%d\n' "$COUNT"
if [ "$FAILED" -ne 0 ]; then
    printf '# %d of %d test(s) failed\n' "$FAILED" "$COUNT"
    exit 1
fi
printf '# %d test(s) passed\n' "$COUNT"
