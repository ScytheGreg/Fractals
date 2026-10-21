#!/usr/bin/env bash

# Colors for status output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

EXE="./discrete_fractal"
ASM_SRC="discrete_fractal.asm"

echo -e "${BLUE}[1/4] Program compilation...${NC}"
nasm -f elf64 "$ASM_SRC" -o discrete_fractal.o
if [ $? -ne 0 ]; then
    echo -e "${RED}NASM compilation failed!${NC}"
    exit 1
fi

ld discrete_fractal.o -o discrete_fractal
if [ $? -ne 0 ]; then
    echo -e "${RED}Linking failed!${NC}"
    exit 1
fi
rm discrete_fractal.o
echo -e "${GREEN}Build succeeded.${NC}\n"

print_stats() {
      if [ $? -ne 0 ]; then
          echo -e "${RED}[X] Program failed!${NC}"
          cat .time_err | grep -E "Command|Exit status"
      else
          echo -e "${GREEN}[V] Success!${NC}"
          # Extract key data from the time report
          local user_time=$(grep "User time" .time_err | awk '{print $4}')
          local sys_time=$(grep "System time" .time_err | awk '{print $4}')
          local max_ram=$(grep "Maximum resident set size" .time_err | awk '{print $6}')

          echo "    User CPU time:           ${user_time}s"
          echo "    System time:             ${sys_time}s"
          echo "    Maximum RSS:             ${max_ram} KB ($(echo "scale=2; $max_ram/1024" | bc) MB)"
      fi
      echo ""
      rm -f .time_err
}

print_test(){
      local title="$1"
      local n_val="$2"
      echo -e "${BLUE}=== TEST: $title (n = $n_val) ===${NC}"
}

# Helper to run a test while measuring time and memory
run_bench() {
    local title="$1"
    local n_val="$2"
    local input_data="$3"

    print_test "$title" "$n_val"

    # Use /usr/bin/time to capture elapsed time and memory (RSS).
    # Discard output to measure the algorithm rather than terminal throughput.
    /usr/bin/time -v $EXE "$n_val" <<< "$input_data" > /dev/null 2> .time_err
    print_stats
}

# ------------------------------------------------------------------------------
# TEST 1: Boundary case n = 0
# ------------------------------------------------------------------------------
# Checks output when no iterations are performed.
TEST_1_INP=$(printf "A\nAAB\nBA\n")
run_bench "Boundary case" "0" "$TEST_1_INP"

# ------------------------------------------------------------------------------
# TEST 2: Exponential growth (streaming and 64 KB buffer)
# ------------------------------------------------------------------------------
# Classic Algae system (A -> AB, B -> A). String length follows the Fibonacci sequence.
# At n=25 it generates 121,393 characters; at n=28, millions of operations.
# Memory use should remain low, mostly for the input buffer.
TEST_2_INP=$(printf "A\nAABA\nBAB\n")
run_bench "Streaming - Algae system (medium load)" "22" "$TEST_2_INP"

# ------------------------------------------------------------------------------
# TEST 3: Deep DFS stack (large n and mremap)
# ------------------------------------------------------------------------------
# Rules: A -> B and B -> A. Output is always exactly one byte.
# The recursion stack depth equals n, testing allocation and memory use at large n.
TEST_3_INP=$(printf "A\nAB\nBA\n")

# Test n = 100,000 (stack uses about 2.4 MB)
run_bench "Deep DFS stack (depth 100k)" "100000" "$TEST_3_INP"

# Test n = 2,000,000 (stack uses about 48 MB)
run_bench "Deep DFS stack (depth 2 million)" "2000000" "$TEST_3_INP"




# Large input test

if [ ! -f  "tests/big_input.in" ]
then
  echo -e "Preparing input data..."
  chmod +x tests/python/big_input.py
  ./tests/python/big_input.py > tests/big_input.in
fi

print_test "Large input test (3 billion characters)" "4"

/usr/bin/time -v $EXE 4 < tests/big_input.in > /dev/null 2> .time_err
print_stats

rm tests/big_input.in
