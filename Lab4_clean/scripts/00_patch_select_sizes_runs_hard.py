from pathlib import Path
import re

path = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean/sql/03_select_index.sql")
text = path.read_text(encoding="utf-8")

print("=== BEFORE: suspicious lines ===")
for i, line in enumerate(text.splitlines(), start=1):
    if (
        "ARRAY" in line
        or "measure_select_table" in line
        or "Running SELECT" in line
        or "10000" in line
        or "50000" in line
        or "100000" in line
        or "500000" in line
        or "1000000" in line
    ):
        print(f"{i}: {line}")

new_sizes = "ARRAY[10, 100, 1000, 10000, 50000, 100000, 500000, 1000000]"

old_size_patterns = [
    r"ARRAY\s*\[\s*10000\s*,\s*50000\s*,\s*100000\s*,\s*500000\s*,\s*1000000\s*\]",
    r"ARRAY\s*\[\s*10\s*,\s*100\s*,\s*1000\s*,\s*10000\s*,\s*50000\s*,\s*100000\s*,\s*500000\s*,\s*1000000\s*\]",
]

changed = False

for pat in old_size_patterns:
    text2, n = re.subn(pat, new_sizes, text, flags=re.S)
    if n:
        print(f"patched size array by pattern: {pat}, replacements={n}")
        text = text2
        changed = True

# Если размеры заданы не ARRAY[...], а через VALUES (...), заменяем блок размеров внутри DO.
text2, n = re.subn(
    r"FOR\s+v_rows\s+IN\s+SELECT\s+\*\s+FROM\s+unnest\s*\(\s*ARRAY\s*\[[^\]]+\]\s*\)",
    f"FOR v_rows IN SELECT * FROM unnest({new_sizes})",
    text,
    flags=re.S | re.I,
)
if n:
    print(f"patched FOR v_rows unnest array, replacements={n}")
    text = text2
    changed = True

# Если есть FOREACH v_rows IN ARRAY ARRAY[...]
text2, n = re.subn(
    r"FOREACH\s+v_rows\s+IN\s+ARRAY\s+ARRAY\s*\[[^\]]+\]",
    f"FOREACH v_rows IN ARRAY {new_sizes}",
    text,
    flags=re.S | re.I,
)
if n:
    print(f"patched FOREACH array, replacements={n}")
    text = text2
    changed = True

# Меняем количество прогонов в вызовах measure_select_table(..., 200, 5) -> (..., 200, 6)
text2, n = re.subn(
    r"(measure_select_table\s*\([^;]*?,\s*200\s*,\s*)5(\s*\))",
    r"\g<1>6\2",
    text,
    flags=re.S,
)
if n:
    print(f"patched measure_select_table runs, replacements={n}")
    text = text2
    changed = True

# На случай если probes уже не 200, но последний аргумент 5
text2, n = re.subn(
    r"(measure_select_table\s*\([^;]*?,\s*\d+\s*,\s*)5(\s*\))",
    r"\g<1>6\2",
    text,
    flags=re.S,
)
if n:
    print(f"patched fallback measure_select_table runs, replacements={n}")
    text = text2
    changed = True

path.write_text(text, encoding="utf-8")

print("\n=== AFTER: suspicious lines ===")
for i, line in enumerate(text.splitlines(), start=1):
    if (
        "ARRAY" in line
        or "measure_select_table" in line
        or "Running SELECT" in line
        or "10000" in line
        or "50000" in line
        or "100000" in line
        or "500000" in line
        or "1000000" in line
    ):
        print(f"{i}: {line}")

if not changed:
    print("\nWARNING: automatic patch did not find expected patterns.")
    print("Show the grep output and we will patch by exact line numbers.")
else:
    print("\nOK: patch attempted.")
