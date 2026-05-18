#!/usr/bin/env bash
# tests/python/fuzz_runner.sh

N=$(( 22 ))
GEN_DIR="tests/python"

# 1. Generowanie losowego testu
python3 "${GEN_DIR}/generator.py" --mode random --rules 8 --axiom-len 10 --max-rule-len 5 > .temp_input.txt

# 2. Uruchomienie programu asemblerowego (ścieżka relatywna do korzenia)
./discrete_fractal "$N" < .temp_input.txt > .out_asm.txt 2> .err_asm.txt
if [ $? -ne 0 ]; then
echo "FAIL: Program ASM wywalił się! (n=$N)"
cat .err_asm.txt
rm -f .temp_input.txt .out_asm.txt .out_ref.txt .err_asm.txt
exit 1
fi

# 3. Uruchomienie referencji w Pythonie
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

# 4. Porównanie wyników
diff .out_asm.txt .out_ref.txt > /dev/null
if [ $? -ne 0 ]; then
echo "FAIL: Niezgodność wyników! (n=$N)"
echo "--- WEJŚCIE ---"
cat .temp_input.txt
echo "--- WYNIK ASM ---"
cat .out_asm.txt
echo "--- WYNIK REF ---"
cat .out_ref.txt
rm -f .temp_input.txt .out_asm.txt .out_ref.txt .err_asm.txt
exit 1
fi

# Sprzątanie po udanym teście
rm -f .temp_input.txt .out_asm.txt .out_ref.txt .err_asm.txt
exit 0