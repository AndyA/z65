.PHONY: all

%.s19: %.a65
	docker run --platform i386 --rm -it -v $(PWD):/src \
		as65 -l -m -s -w -h0 src/$<

%.s19: %.a65c
	docker run --platform i386 --rm -it -v $(PWD):/src \
		as65 -l -m -s -w -h0 -x src/$<

../../src/test/data/%.s19: %.s19
	cp $< $@

all: ../../src/test/data/6502_functional_test.s19 \
	../../src/test/data/65C02_extended_opcodes_test.s19

6502_functional_test.s19: report.i65
65C02_extended_opcodes_test.s19: report.i65

clean:
	rm -f *.s19 *.lst *.bin *.hex
