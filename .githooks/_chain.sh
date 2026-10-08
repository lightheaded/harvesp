# shellcheck shell=sh
# _chain.sh - run the hook of the same name from the global hooks directory.
#
# This repository sets core.hooksPath=.githooks. Then git does not run the
# hooks from the global core.hooksPath. To keep those hooks active, each hook
# here calls chain_hook after its own checks pass.
#
# chain_hook NAME [ARGS...] replaces the current process with the global hook
# NAME, with the same arguments and stdin. If no global hooks directory is set,
# it uses the hooks directory inside .git. If no hook is found, it exits 0.

chain_hook() {
	_name=$1
	shift
	_top=$(git rev-parse --show-toplevel) || exit 2
	_self=$(cd "$_top/.githooks" 2>/dev/null && pwd -P)

	_dir=$(git config --global --get core.hooksPath 2>/dev/null || true)
	if [ -n "$_dir" ]; then
		case $_dir in
		"~") _dir=$HOME ;;
		"~/"*) _dir=$HOME/${_dir#"~/"} ;;
		/*) ;;
		*) _dir=$_top/$_dir ;;
		esac
	else
		_dir=$(git rev-parse --git-common-dir)/hooks
	fi

	[ -d "$_dir" ] || exit 0
	_real=$(cd "$_dir" && pwd -P)
	[ "$_real" = "$_self" ] && exit 0
	[ -f "$_real/$_name" ] && [ -x "$_real/$_name" ] || exit 0
	exec "$_real/$_name" "$@"
}
