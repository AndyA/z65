.PHONY: all

%.s19: %.a65
	docker run --platform i386 --rm -it -v $(PWD):/src \
		as65 -l -m -s -w -h0 src/$<

all: 6502_functional_test.s19

clean:
	rm -f *.s19 *.lst *.bin *.hex
