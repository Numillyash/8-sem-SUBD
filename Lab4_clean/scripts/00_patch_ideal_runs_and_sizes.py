from pathlib import Path
import re

BASE = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean")

targets = [
    BASE / "sql/03_select_index.sql",
    BASE / "sql/04_insert_indexes.sql",
    BASE / "sql/05_update_indexes.sql",
]

new_sizes = "ARRAY[10, 100, 1000, 10000, 50000, 100000, 500000, 1000000]"

array_patterns = [
    re.compile(r"ARRAY\s*\[\s*10000\s*,\s*50000\s*,\s*100000\s*,\s*500000\s*,\s*1000000\s*\]", re.S),
    re.compile(r"ARRAY\s*\[\s*10\s*,\s*100\s*,\s*1000\s*,\s*10000\s*,\s*50000\s*,\s*100000\s*,\s*500000\s*,\s*1000000\s*\]", re.S),
]

for path in targets:
    text = path.read_text(encoding="utf-8")

    for pat in array_patterns:
        text = pat.sub(new_sizes, text)

    if path.name == "03_select_index.sql":
        text = re.sub(
            r"(measure_select_table\s*\([^;]*?,\s*200\s*,\s*)5(\s*\))",
            r"\g<1>6\2",
            text,
            flags=re.S,
        )

    if path.name == "04_insert_indexes.sql":
        text = re.sub(
            r"(measure_insert_table\s*\([^;]*?,\s*1000\s*,\s*)5(\s*\))",
            r"\g<1>6\2",
            text,
            flags=re.S,
        )

    if path.name == "05_update_indexes.sql":
        text = re.sub(
            r"(measure_update_table\s*\([^;]*?,\s*1000\s*,\s*)5(\s*\))",
            r"\g<1>6\2",
            text,
            flags=re.S,
        )

    path.write_text(text, encoding="utf-8")
    print(f"patched: {path}")
