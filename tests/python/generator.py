#!/usr/bin/env python3
import random
import argparse
import string

def generate_random_test(num_rules, axiom_len, max_rule_len):
    # Use safe, visible ASCII characters ('!' through '~'), excluding special characters.
    alphabet = [c for c in string.ascii_letters + string.digits + "+-=[]{}()"]
    random.shuffle(alphabet)

    # Generate the axiom (starting string).
    axiom = "".join(random.choices(alphabet, k=axiom_len))

    # Choose symbols that will have replacement rules.
    rule_chars = random.sample(alphabet, min(num_rules, len(alphabet)))

    rules = []
    for char in rule_chars:
        # Choose a random replacement length (zero creates an empty rule).
        r_len = random.randint(0, max_rule_len)
        replacement = "".join(random.choices(alphabet, k=r_len))
        rules.append(f"{char}{replacement}")

    return axiom, rules

def generate_deep_stack_test(depth):
    # Generate a closed permutation cycle: A -> B -> C -> ... -> A.
    # Output is always one byte, while DFS stack depth grows linearly.
    alphabet = list(string.ascii_uppercase)
    rules = []
    for i in range(len(alphabet)):
        next_char = alphabet[(i + 1) % len(alphabet)]
        rules.append(f"{alphabet[i]}{next_char}")
    return alphabet[0], rules

def generate_explosion_test():
    # Classic growth pattern: each symbol doubles or triples the string length.
    axiom = "X"
    rules = [
        "XFX+F-F+X",
        "FFF",
        "+-",
        "-+"
    ]
    return axiom, rules

def main():
    parser = argparse.ArgumentParser(description="Test generator for L-systems (discrete_fractal)")
    parser.add_argument("--mode", choices=["random", "deep", "explosion"], default="random", help="Generation mode")
    parser.add_argument("--rules", type=int, default=10, help="Number of rules (random mode)")
    parser.add_argument("--axiom-len", type=int, default=5, help="Starting string length (random mode)")
    parser.add_argument("--max-rule-len", type=int, default=4, help="Maximum replacement string length")
    parser.add_argument("--seed", type=int, default=None, help="Random seed for reproducibility")

    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    if args.mode == "random":
        axiom, rules = generate_random_test(args.rules, args.axiom_len, args.max_rule_len)
    elif args.mode == "deep":
        axiom, rules = generate_deep_stack_test(args.max_rule_len)
    elif args.mode == "explosion":
        axiom, rules = generate_explosion_test()

    # Write the generated test to standard output.
    print(axiom)
    for rule in rules:
        print(rule)

if __name__ == "__main__":
    main()
