VERSION := $(shell sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' fleet-view/info.json)
ZIP := dist/fleet-view_$(VERSION).zip
LUA ?= lua5.2
SAVE ?= fixtures/saves/nn1.zip
TICKS ?= 1800
SHOW_TICK ?= 300

.PHONY: test zip headless bench clean

test:
	$(LUA) tests/run.lua

zip:
	rm -rf dist/stage $(ZIP)
	mkdir -p dist/stage
	cp -r fleet-view dist/stage/fleet-view_$(VERSION)
	cd dist/stage && zip -qr ../fleet-view_$(VERSION).zip fleet-view_$(VERSION)
	rm -rf dist/stage
	@echo built $(ZIP)

headless: zip
	tools/headless.sh $(ZIP) $(SAVE)

bench: zip
	@for m in A B; do for i in 1 2 3; do echo "== $$m run $$i"; SHOW_TICK=$(SHOW_TICK) STATS_EVERY=0 tests/bench/bench.sh $$m $(TICKS); done; done

clean:
	rm -rf dist
