# Root Makefile - delegates to each subproject's own Makefile.
#
# To add a new project, just drop a directory with its own Makefile
# at the top level; it will be picked up automatically.

.PHONY: all clean check-copies

all:
	@for dir in */; do \
		if [ -f "$$dir/Makefile" ]; then \
			echo "==> Building $$dir"; \
			$(MAKE) -C "$$dir" all || exit 1; \
		fi; \
	done

clean:
	@for dir in */; do \
		if [ -f "$$dir/Makefile" ]; then \
			echo "==> Cleaning $$dir"; \
			$(MAKE) -C "$$dir" clean || exit 1; \
		fi; \
	done

# The four banked linker configs are copies of 6502-CRT's generated ones, and
# 6502.inc / 6502-VDP.inc are copies kept in step by hand. A stale config links
# and boots and reads the wrong bank, so check rather than hope.
check-copies:
	@python3 tools/check-copies.py
