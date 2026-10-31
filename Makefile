.PHONY: test build app install clean

test:
	swift test

build:
	swift build -c release

app: build

clean:
	rm -rf .build build
