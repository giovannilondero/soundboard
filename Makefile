BIN := $(HOME)/Soundboard/bin/soundboard

.PHONY: build install uninstall restart doctor

build:
	swift build -c release
	mkdir -p bin && rm -f $(BIN) && cp .build/release/soundboard $(BIN) && codesign -s - -f $(BIN)

install: build
	$(BIN) install
	ln -sf $(BIN) /opt/homebrew/bin/soundboard

restart: build
	$(BIN) quit || true
	sleep 0.5
	$(BIN) install

uninstall:
	$(BIN) uninstall
	rm -f /opt/homebrew/bin/soundboard

doctor:
	$(BIN) doctor
