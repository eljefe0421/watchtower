.PHONY: build run clean install

BINARY = .build/Watchtower
SOURCES = $(wildcard Sources/Watchtower/*.swift)
TARGET = arm64-apple-macosx14.0

build: $(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p .build
	swiftc -o $(BINARY) -target $(TARGET) -parse-as-library -swift-version 5 -O $(SOURCES)

run: build
	$(BINARY)

clean:
	rm -rf .build

install: build
	cp $(BINARY) /usr/local/bin/watchtower

install-hooks:
	$(BINARY) --install-hooks
