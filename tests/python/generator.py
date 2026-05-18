#!/usr/bin/env python3
import random
import argparse
import string

def generate_random_test(num_rules, axiom_len, max_rule_len):
    # Używamy bezpiecznych, widocznych znaków ASCII (od '!' do '~', pomijając znaki specjalne)
    alphabet = [c for c in string.ascii_letters + string.digits + "+-=[]{}()"]
    random.shuffle(alphabet)

    # Generowanie aksjomatu (ciągu startowego)
    axiom = "".join(random.choices(alphabet, k=axiom_len))

    # Wybieramy symbole, które będą miały swoje reguły
    rule_chars = random.sample(alphabet, min(num_rules, len(alphabet)))

    rules = []
    for char in rule_chars:
        # Losowa długość ciągu zastępującego (może być 0 dla pustej reguły)
        r_len = random.randint(0, max_rule_len)
        replacement = "".join(random.choices(alphabet, k=r_len))
        rules.append(f"{char}{replacement}")

    return axiom, rules

def generate_deep_stack_test(depth):
    # Generuje zamknięty cykl permutacji: A -> B -> C -> ... -> A
    # Rozmiar wyjścia to zawsze 1 bajt, ale stos DFS idzie liniowo w dół
    alphabet = list(string.ascii_uppercase)
    rules = []
    for i in range(len(alphabet)):
        next_char = alphabet[(i + 1) % len(alphabet)]
        rules.append(f"{alphabet[i]}{next_char}")
    return alphabet[0], rules

def generate_explosion_test():
    # Klasyczna eksplozja: każdy znak podwaja lub potraja długość
    axiom = "X"
    rules = [
        "XFX+F-F+X",
        "FFF",
        "+-",
        "-+"
    ]
    return axiom, rules

def main():
    parser = argparse.ArgumentParser(description="Generator testów dla L-systemów (discrete_fractal)")
    parser.add_argument("--mode", choices=["random", "deep", "explosion"], default="random", help="Tryb generowania")
    parser.add_argument("--rules", type=int, default=10, help="Liczba reguł (dla trybu random)")
    parser.add_argument("--axiom-len", type=int, default=5, help="Długość ciągu startowego (dla trybu random)")
    parser.add_argument("--max-rule-len", type=int, default=4, help="Maksymalna długość prawej strony reguły")
    parser.add_argument("--seed", type=int, default=None, help="Ziarno generatora losowego (powtarzalność)")

    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    if args.mode == "random":
        axiom, rules = generate_random_test(args.rules, args.axiom_len, args.max_rule_len)
    elif args.mode == "deep":
        axiom, rules = generate_deep_stack_test(args.max_rule_len)
    elif args.mode == "explosion":
        axiom, rules = generate_explosion_test()

    # Wypisanie gotowego testu na standardowe wyjście
    print(axiom)
    for rule in rules:
        print(rule)

if __name__ == "__main__":
    main()