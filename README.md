# Testy projektu

## Wymagania

* Python

## Konfiguracja

1. Umieść katalog `tests` w korzeniu projektu, obok katalogu `discrete_fractal` oraz pliku `Makefile`.

2. Nadaj uprawnienia wykonywania skryptom:

```bash
chmod +x tests/python/* tests/benchmark.sh
```

3. Dodaj do pliku `Makefile` następujące cele:

```make
bench:
	./tests/benchmark.sh
	./tests/python/streaming_benchmark.py

fuzz:
	./tests/python/checker.py
	./tests/python/fuzz_runner.sh
```

## Uruchomienie

### Testy poprawności

```bash
make fuzz
```

Uruchamia testy sprawdzające:

* poprawność generowanego wyjścia,
* obsługę błędów i przypadków brzegowych.

### Testy wydajności

```bash
make bench
```

Uruchamia benchmarki mierzące:

* czas wykonania,
* zużycie pamięci.

Testy wydajności **nie sprawdzają poprawności wyników**.
