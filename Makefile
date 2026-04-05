.PHONY: build run start stop clean install

BINARY = .build/Watchtower
SOURCES = $(wildcard Sources/Watchtower/*.swift)
TARGET = arm64-apple-macosx14.0

build: $(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p .build
	swiftc -o $(BINARY) -target $(TARGET) -parse-as-library -swift-version 5 -O $(SOURCES)

# Run in foreground (for debugging)
run: build
	$(BINARY)

# Launch as background process (survives terminal close)
start: build stop
	@nohup $(BINARY) > /dev/null 2>&1 & disown
	@sleep 1
	@echo "Watchtower started (PID $$(pgrep -f '.build/Watchtower'))"
	@echo "Logs: tail -f /tmp/watchtower.log"

# Stop background process
stop:
	@pkill -f '.build/Watchtower' 2>/dev/null || true

# Show status
status:
	@if pgrep -f '.build/Watchtower' > /dev/null 2>&1; then \
		echo "Watchtower running (PID $$(pgrep -f '.build/Watchtower'))"; \
	else \
		echo "Watchtower not running"; \
	fi

clean:
	rm -rf .build

install: build
	cp $(BINARY) /usr/local/bin/watchtower
