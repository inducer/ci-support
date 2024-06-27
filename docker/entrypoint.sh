# According to
# https://docs.gitlab.com/runner/shells/#shell-profile-loading
# Gitlab runner's docker executor does not load shell startup files,
# because that's a great idea.
cmd=()
for i in "$@"; do
  cmd+=("$(echo "$i"| sed "/exec/s/bash/bash --login/g")")
done
echo "Using rewritten shell invocation received from executor."
echo "See https://github.com/inducer/ci-support/blob/main/docker/entrypoint.sh for details."
"${cmd[@]}"
retcode="$?"
echo "return code from command: $retcode"
exit "$retcode"

