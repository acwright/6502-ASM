# Root Makefile - delegates to each subproject's own Makefile.
#
# To add a new project, just drop a directory with its own Makefile
# at the top level; it will be picked up automatically.

.PHONY: all clean

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
