# Attempt to work with either sail from opam or built from repo in SAIL_DIR
ifneq ($(SAIL_DIR),)
# Use sail repo in SAIL_DIR
SAIL:=$(SAIL_DIR)/sail
export SAIL_DIR
else
# Use sail from opam package
SAIL_DIR:=$(shell opam var sail:share)
SAIL:=sail
endif

ISLA_SAIL=isla-sail

SAIL_X86_DIR=sail-x86
SAIL_X86_MODEL_DIR=$(SAIL_X86_DIR)/model
SAIL_CHERI_MODEL_DIR=src

# FIXME: needs a decent way to include mono_rewrites.sail for just the IR target
PRELUDE_SAILS = $(SAIL_X86_MODEL_DIR)/prelude.sail \
		test-generation/mono.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_prelude.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_types.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_cap_common.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_memory_tags.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_register_types.sail \
		$(SAIL_X86_MODEL_DIR)/registers.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_registers.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_register_accessors.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_opcode_ext.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_memory_accessors.sail \
		$(SAIL_X86_MODEL_DIR)/init.sail \
		$(SAIL_X86_MODEL_DIR)/config.sail \
		$(SAIL_CHERI_MODEL_DIR)/cheri_logging.sail
MODEL_SAILS=$(SAIL_X86_MODEL_DIR)/step.sail \
	    $(SAIL_CHERI_MODEL_DIR)/cheri_decoding_and_spec_utils.sail \
	    $(SAIL_CHERI_MODEL_DIR)/cheri_arith_and_logic.sail \
	    $(SAIL_CHERI_MODEL_DIR)/cheri_move.sail \
	    $(SAIL_CHERI_MODEL_DIR)/cheri_one_byte_opcodes_dispatch.sail \
	    $(SAIL_CHERI_MODEL_DIR)/cheri_two_byte_opcodes_dispatch.sail
MAIN_SAIL=$(SAIL_X86_MODEL_DIR)/main.sail
ALL_SAILS=$(PRELUDE_SAILS) $(MODEL_SAILS) $(MAIN_SAIL)

CC?=gcc

GMP_FLAGS = $(shell pkg-config --cflags gmp)
# N.B. GMP does not have pkg-config metadata on Ubuntu 18.04 so default to -lgmp
GMP_LIBS := $(shell pkg-config --libs gmp || echo -lgmp)

ZLIB_FLAGS = $(shell pkg-config --cflags zlib)
ZLIB_LIBS = $(shell pkg-config --libs zlib)

all: x86_emulator

.PHONY: all clean interactive

x86_emulator.c: $(ALL_SAILS)
	$(SAIL) -c -memo_z3 $(SAIL_FLAGS) $(ALL_SAILS) > x86_emulator.c.temp
	mv x86_emulator.c.temp x86_emulator.c

x86_emulator: x86_emulator.c $(SAIL_DIR)/lib/*.c
	$(CC) -O2 -DHAVE_SETCONFIG x86_emulator.c $(SAIL_DIR)/lib/*.c $(GMP_FLAGS) $(GMP_LIBS) $(ZLIB_FLAGS) $(ZLIB_LIBS) -I $(SAIL_DIR)/lib/ -o x86_emulator

x86.ir: $(ALL_SAILS) sail-x86/test-generation-patches/*.sail
	$(ISLA_SAIL) -mono_rewrites $(foreach file,$(wildcard sail-x86/test-generation-patches/*.sail),-splice $(file)) $(foreach file,$(wildcard test-generation/*.splice.sail),-splice $(file)) -verbose 1 -o x86 $(ALL_SAILS)

x86_gdb.c: $(ALL_SAILS) gdb.sail
	$(SAIL) -c -c_gdb -c_no_main -c_preserve gdb_encode_cap -c_preserve gdb_decode_cap -memo_z3 $(SAIL_FLAGS) $(ALL_SAILS) gdb.sail > x86_gdb.c.temp
	mv x86_gdb.c.temp x86_gdb.c

x86_gdb.o: x86_gdb.c
	$(CC) -g -O2 -DHAVE_SETCONFIG -c x86_gdb.c -I $(SAIL_DIR)/lib/ $(GMP_FLAGS) $(ZLIB_FLAGS)

x86_gdb: x86_gdb.o sail-x86/gdb/*.c
	$(CC) -g -O2 -DHAVE_SETCONFIG x86_gdb.o sail-x86/gdb/*.c $(SAIL_DIR)/lib/*.c $(GMP_FLAGS) $(GMP_LIBS) $(ZLIB_FLAGS) $(ZLIB_LIBS) -I $(SAIL_DIR)/lib/ -o x86_gdb

x86_gdb_cov.c: $(ALL_SAILS) gdb.sail
	$(SAIL) -c -c_gdb -c_no_main -c_preserve gdb_encode_cap -c_preserve gdb_decode_cap -c_coverage all_branches -c_include sail_coverage.h -memo_z3 $(SAIL_FLAGS) $(ALL_SAILS) gdb.sail > x86_gdb_cov.c.temp
	mv x86_gdb_cov.c.temp x86_gdb_cov.c

x86_gdb_cov.o: x86_gdb_cov.c
	$(CC) -g -O2 -DHAVE_SETCONFIG -c x86_gdb_cov.c -I $(SAIL_DIR)/lib/ $(GMP_FLAGS) $(ZLIB_FLAGS)

x86_gdb_cov: x86_gdb_cov.o sail-x86/gdb/*.c
	$(CC) -g -O2 -DHAVE_SETCONFIG x86_gdb_cov.o sail-x86/gdb/*.c $(SAIL_DIR)/lib/*.c $(SAIL_DIR)/lib/coverage/libsail_coverage.a -lpthread -ldl $(GMP_FLAGS) $(GMP_LIBS) $(ZLIB_FLAGS) $(ZLIB_LIBS) -I $(SAIL_DIR)/lib/ -o x86_gdb_cov

interactive:
	$(SAIL) -i -memo_z3 $(SAIL_FLAGS) $(ALL_SAILS)

clean:
	rm -f x86_emulator.c x86_emulator x86.ir x86_gdb.c x86_gdb.o x86_gdb x86_gdb_cov.c x86_gdb_cov.o x86_gdb_cov
