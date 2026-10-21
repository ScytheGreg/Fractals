#!/usr/bin/env bash
# tests/python/fuzz_runner.sh

N=$(( 22 ))
GEN_DIR="tests/python"

# 1. Generate a random test.
python3 "${GEN_DIR}/generator.py" --mode random --rules 8 --axiom-len 10 --max-rule-len 5 > .temp_input.txt

# 2. Run the assembly program (path relative to the repository root).
./discrete_fractal "$N" < .temp_input.txt > .out_asm.txt 2> .err_asm.txt
if [ $? -ne 0 ]; then
echo "FAIL: Assembly program crashed (n=$N)."
cat .err_asm.txt
rm -f .temp_input.txt .out_asm.txt .out_ref.txt .err_asm.txt
exit 1
fi

# 3. Run the Python reference implementation.
python3 -c "
import sys
lines = open('.temp_input.txt').read().split('\n')
start_str = lines[0]
rules = {l[0]: l[1:] for l in lines[1:] if l}
output = []
def dfs(char, depth):
    if depth == 0 or char not in rules: output.append(char)
    else:
        for c in rules[char]: dfs(c, depth - 1)
for c in start_str: dfs(c, $N)
print(''.join(output))
" > .out_ref.txt

# 4. Compare results.
diff .out_asm.txt .out_ref.txt > /dev/null
if [ $? -ne 0 ]; then
echo "FAIL: Output mismatch (n=$N)."
echo "--- INPUT ---"
cat .temp_input.txt
echo "--- ASSEMBLY OUTPUT ---"
cat .out_asm.txt
echo "--- REFERENCE OUTPUT ---"
cat .out_ref.txt
rm -f .temp_input.txt .out_asm.txt .out_ref.txt .err_asm.txt
exit 1
fi

if ! ./tests/invalid_input_tests.sh ./discrete_fractal
then exit 1;
fi

# Clean up after a successful test.
rm -f .temp_input.txt .out_asm.txt .out_ref.txt .err_asm.txt
exit 0
