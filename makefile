# common tasks. pico-8 resolves from PATH by default. for a non-standard
# install, put your path in local.mk (gitignored), e.g.:
#   PICO8 = /path/to/pico8
# or override per-invocation: make run PICO8=/path/to/pico8
-include local.mk
PICO8 ?= pico8
SHRINKO ?= shrinko8
CART ?= v0.3.p8
EXPORT ?= export

.PHONY: run editor count export deploy

run:
	$(PICO8) -run $(CART)

# launch the map editor in your browser:  make editor
# serves locally so the editor can auto-load AND save v0.3.p8 (ctrl-c to stop)
editor:
	@(sleep 1 && open "http://localhost:8765/maptool/editor.html") & python3 maptool/serve.py

# token budget check (shrinko8 rules)
count:
	python3 ../aletha/tools/scripts/count_tokens.py $(CART)

# build the itch.io HTML5 export -> export/index.html + export/index.js
export:
	mkdir -p $(EXPORT)
	$(SHRINKO) $(CART) /tmp/co_min.p8 -m --no-minify-rename
	$(PICO8) /tmp/co_min.p8 -export $(EXPORT)/index.html

# export + commit + push. GitHub Actions then pushes export/ to itch.io
# (bonnie-studios/cortex-override:html5) via butler. One-time setup:
#   - repo secret BUTLER_API_KEY = your itch.io API key
deploy: export
	git add $(EXPORT)/index.html $(EXPORT)/index.js
	git commit -m "deploy: update itch.io build" || echo "nothing to commit"
	git push
