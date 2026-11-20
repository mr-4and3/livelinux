all: safe-stick

.PHONY: safe-stick
safe-stick:
	cd safe-stick && cargo build --release