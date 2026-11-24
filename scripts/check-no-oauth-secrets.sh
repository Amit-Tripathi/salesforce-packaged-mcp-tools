#!/bin/sh
# Blocks commits that would add OAuth client IDs or secrets to this public repo.
# The External Client App's consumer key/secret live only in the Dev Hub (and the
# gitignored pbo-only/.../extlClntAppGlobalOauthSets/ folder).
fail=0

files=$(git diff --cached --name-only --diff-filter=ACMR)
for f in $files; do
  case "$f" in
    *extlClntAppGlobalOauthSets/*|*.ecaGlblOauth-meta.xml)
      echo "BLOCKED: $f holds ECA global OAuth settings (consumer key/secret). Keep it out of git."
      fail=1 ;;
  esac
done

if git diff --cached -U0 | grep -E '^\+' | grep -v '^+++' | \
   grep -iqE '<consumer(Key|Secret)>|client_secret[[:space:]]*[:=]|clientSecret[[:space:]]*[:=]|client_id[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9._]{20,}|3MVG[A-Za-z0-9._]{20,}'; then
  echo "BLOCKED: staged changes contain what looks like an OAuth client ID or secret."
  fail=1
fi

[ $fail -eq 0 ] || { echo "Commit aborted. Remove OAuth credentials (see README: they stay in the Dev Hub)."; exit 1; }
