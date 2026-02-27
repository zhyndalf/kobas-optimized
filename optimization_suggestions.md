# KOBAS 3.0.3 Performance Optimization Suggestions

## Profiling Baseline (336s on ARM 607-core machine, `-n 128`)

| Component | % | ~Seconds | Source |
|---|---|---|---|
| BLAST execution (`__communicate_with_poll`) | 19% | ~64s | subprocess.py:1178 |
| XML parsing (`NCBIXML.parse`) | 31% | ~104s | Bio/Blast/NCBIXML.py:833 |
| DB: `name_from_gid` | 7% | ~24s | dbutils.py:149 |
| DB: `entrez_gene_ids_from_gid` | 6% | ~20s | dbutils.py:177 |
| DB: `pathways_from_gid` | 7% | ~24s | dbutils.py:202 |
| DB: `diseases_from_gid` | 6% | ~20s | dbutils.py:208 |
| DB: `gos_from_gid` | 7% | ~24s | dbutils.py:211 |
| DB: `goslims_from_gid` | 7% | ~24s | dbutils.py:224 |

---

## Optimization 1: Switch BLAST output from XML (outfmt=5) to tabular (outfmt=6)

**Target:** Eliminate 31% XML parsing + reduce 19% subprocess pipe overhead

**Current code:** `annot.py:91`
```python
cline = ...Commandline(cmd=blastcmd, query=infile, db=database, outfmt=5, num_threads=nCPUs)
```

**Change to:** `outfmt=6` and use existing `BlastoutTabReader`/`BlastoutTabSelector`

**Expected savings:** ~130-140s

---

## Optimization 2: Preload SQLite data into in-memory dicts

**Target:** Eliminate 40% DB query overhead (6 functions, each 6-7%)

**Current code:** `output.py:57-103` does 5 individual SQL queries per gene

**Change to:** Bulk-load all tables into Python dicts at startup, replace SQL queries with dict lookups

**Expected savings:** ~100-120s

---

## Optimization 3: Write BLAST output to file instead of piping through memory

**Target:** Reduce remaining subprocess pipe overhead

**Current code:** `annot.py:92`
```python
blastout, blasterr = cline()  # captures ALL stdout in memory
```

**Change to:** BLAST writes to temp file, Python reads from file

**Expected savings:** ~10-20s

---

## Conservative Total Estimate: 336s → ~80-120s (target: <150s)
