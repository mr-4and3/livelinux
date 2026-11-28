all: safe-stick

.PHONY: safe-stick release-bundle patch-version minor-version major-version
safe-stick:
	cd safe-stick && PATH="$(HOME)/.cargo/bin:$$PATH" cargo build --release

patch-version:
	./version.sh patch
minor-version:
	./version.sh minor
major-version:
	./version.sh major

release-bundle:
	@set -eu; \
	branch="$$(git branch --show-current)"; \
	if [ "$$branch" != "main" ]; then \
		echo "release-bundle must be run on main (current branch: $${branch:-detached HEAD})." >&2; \
		exit 1; \
	fi; \
	if [ -n "$$(git status --porcelain --untracked-files=normal)" ]; then \
		echo "release-bundle requires a clean working tree; commit or remove all changes first:" >&2; \
		git status --short >&2; \
		exit 1; \
	fi
	$(MAKE) safe-stick
	@set -eu; \
	bundle_dir="$$(mktemp -d)"; \
	trap 'rm -rf "$$bundle_dir"' EXIT; \
	version="$$(sed -n 's/^version = "\([^"]*\)"/\1/p' safe-stick/Cargo.toml)"; \
	if [ -z "$$version" ]; then \
		echo "Could not read the Safe Stick version from safe-stick/Cargo.toml." >&2; \
		exit 1; \
	fi; \
	archive="dist/safe-stick-$$version.tar.gz"; \
	mkdir -p "$$bundle_dir/safe-stick"; \
	install -m 0755 safe-stick/target/release/safe-stick "$$bundle_dir/safe-stick/safe-stick"; \
	cp README.md License.txt "$$bundle_dir/safe-stick/"; \
	git ls-files -z -- scripts | tar --null -T - -cf - | tar -xf - -C "$$bundle_dir/safe-stick"; \
	mkdir -p dist; \
	tar -czf "$$archive" -C "$$bundle_dir" safe-stick; \
	echo "Created $$archive"