# Debug Instructions for KOBAS Optimization Bug

## Problem Summary
The optimized version (commit 4729af4) runs faster but produces incorrect results - many pathway annotations are missing in the output.

## Root Cause Hypothesis
The preloading code in `_preload_gene_data()` may have a bug in how it stores or retrieves pathway data from the in-memory dictionaries.

## Step 1: Verify Database Integrity

Run these commands to understand the data structure:

```bash
cd /nfs02/home/hfzeng/Kobas/case

# Count total pathway associations
sqlite3 sqlite3/ztr.db "SELECT COUNT(*) FROM GenePathways"

# Count unique genes with pathways
sqlite3 sqlite3/ztr.db "SELECT COUNT(DISTINCT gid) FROM GenePathways"

# Show top 5 genes with most pathways
sqlite3 sqlite3/ztr.db "SELECT gid, COUNT(*) as pathway_count FROM GenePathways GROUP BY gid ORDER BY pathway_count DESC LIMIT 5"

# Sample some actual data
sqlite3 sqlite3/ztr.db "SELECT GenePathways.gid, Pathways.db, Pathways.id, Pathways.name FROM GenePathways JOIN Pathways ON GenePathways.pid = Pathways.pid LIMIT 10"
```

Save the output to a file:
```bash
sqlite3 sqlite3/ztr.db "SELECT COUNT(*) FROM GenePathways" > debug_db_stats.txt
sqlite3 sqlite3/ztr.db "SELECT COUNT(DISTINCT gid) FROM GenePathways" >> debug_db_stats.txt
sqlite3 sqlite3/ztr.db "SELECT gid, COUNT(*) as pathway_count FROM GenePathways GROUP BY gid ORDER BY pathway_count DESC LIMIT 5" >> debug_db_stats.txt
```

## Step 2: Add Debug Output to Preloading Code

Edit the file: `/nfs02/home/hfzeng/Miniconda3/envs/kobas3/lib/python2.7/site-packages/kobas/dbutils.py`

Add these debug print statements after line 57 (after the pathways preloading try/except block):

```python
        except sqlite3.OperationalError:
            pass

        # DEBUG: Print preloading statistics
        print "DEBUG: Loaded %d genes with pathways" % len(self._pathways)
        print "DEBUG: Total pathway entries:", sum(len(v) for v in self._pathways.values())
        if self._pathways:
            sample_gid = self._pathways.keys()[0]
            print "DEBUG: Sample gid:", sample_gid
            print "DEBUG: Sample pathways:", self._pathways[sample_gid][:3]
```

## Step 3: Run Test with Debug Output

```bash
cd /nfs02/home/hfzeng/Kobas/case
source /nfs02/home/ljh/kit/hpckit-install/HPCKIT/25.1.0.SPC001/setvars.sh --force

# Run with a small subset to see debug output quickly
kobas-annotate -i ./seq_pep/ztr.pep.fasta -o ztr_debug_test -k ./ -v /nfs02/home/hfzeng/Kobas/ncbi-blast-2.16.0+/bin -y ./seq_pep -q ./sqlite3 -s ztr -n 128 2>&1 | head -50 > debug_output.txt
```

## Step 4: Create Minimal Test Script

Create a test script to isolate the issue:

```bash
cat > test_preload.py << 'EOF'
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
sys.path.insert(0, '/nfs02/home/hfzeng/Miniconda3/envs/kobas3/lib/python2.7/site-packages')

from kobas import dbutils

# Load the database
print "Loading database..."
db = dbutils.KOBASDB('/nfs02/home/hfzeng/Kobas/case/sqlite3/ztr.db')

print "\n=== Preloaded Data Statistics ==="
print "Genes with pathways:", len(db._pathways)
print "Total pathway entries:", sum(len(v) for v in db._pathways.values())

# Test a specific gene
test_gids = ['ztr:100381270', 'ztr:100381271', 'ztr:100381272']

for test_gid in test_gids:
    print "\n=== Testing gid:", test_gid, "==="

    # Check if in preloaded dict
    if test_gid in db._pathways:
        print "Found in _pathways dict"
        print "Number of pathways:", len(db._pathways[test_gid])
        print "First 3 pathways:", db._pathways[test_gid][:3]
    else:
        print "NOT found in _pathways dict"

    # Test the actual method
    pathways = list(db.pathways_from_gid(test_gid))
    print "pathways_from_gid returned:", len(pathways), "pathways"
    if pathways:
        print "First pathway:", pathways[0]

# Compare with direct SQL query
print "\n=== Direct SQL Query Comparison ==="
for test_gid in test_gids[:1]:  # Just test one
    print "Testing gid:", test_gid

    # Direct query (original method)
    result = db.con.execute(
        'SELECT Pathways.db, Pathways.id, Pathways.name FROM GenePathways, Pathways WHERE GenePathways.gid = ? AND GenePathways.pid = Pathways.pid',
        (test_gid,)
    ).fetchall()
    print "Direct SQL returned:", len(result), "pathways"
    if result:
        print "First result:", dict(result[0])
EOF

python test_preload.py > test_preload_output.txt 2>&1
```

## Step 5: Compare Original vs Optimized

```bash
cd /nfs02/home/hfzeng/Kobas/case

# If you still have the original results
if [ -f ztr_result10_original ]; then
    echo "Comparing line counts..."
    wc -l ztr_result10_original
    wc -l ztr_result10

    echo "Comparing unique pathways..."
    grep "KEGG PATHWAY" ztr_result10_original | sort | uniq -c | wc -l
    grep "KEGG PATHWAY" ztr_result10 | sort | uniq -c | wc -l
fi
```

## Step 6: Collect All Debug Files

```bash
cd /nfs02/home/hfzeng/Kobas/case

# Create a debug package
mkdir -p debug_results
cp debug_db_stats.txt debug_results/ 2>/dev/null
cp debug_output.txt debug_results/ 2>/dev/null
cp test_preload_output.txt debug_results/ 2>/dev/null

# Create a summary
cat > debug_results/SUMMARY.txt << 'EOF'
Debug Results Summary
=====================

Please include the contents of:
1. debug_db_stats.txt - Database statistics
2. debug_output.txt - Debug output from kobas-annotate
3. test_preload_output.txt - Output from test script

Also note any errors or unexpected behavior you observed.
EOF

echo "Debug files collected in debug_results/"
ls -lh debug_results/
```

## What to Send Back

Please send me the contents of these files:
1. `debug_results/debug_db_stats.txt`
2. `debug_results/test_preload_output.txt`
3. Any error messages you see

You can either:
- Copy the file contents and paste them
- Or commit the debug_results folder and push to GitHub

## Quick Commands Summary

```bash
# Navigate to case directory
cd /nfs02/home/hfzeng/Kobas/case

# Run all database queries
sqlite3 sqlite3/ztr.db "SELECT COUNT(*) FROM GenePathways" > debug_db_stats.txt
sqlite3 sqlite3/ztr.db "SELECT COUNT(DISTINCT gid) FROM GenePathways" >> debug_db_stats.txt
sqlite3 sqlite3/ztr.db "SELECT gid, COUNT(*) as pathway_count FROM GenePathways GROUP BY gid ORDER BY pathway_count DESC LIMIT 5" >> debug_db_stats.txt

# Create and run test script
cat > test_preload.py << 'EOFTEST'
#!/usr/bin/env python
import sys
sys.path.insert(0, '/nfs02/home/hfzeng/Miniconda3/envs/kobas3/lib/python2.7/site-packages')
from kobas import dbutils

db = dbutils.KOBASDB('/nfs02/home/hfzeng/Kobas/case/sqlite3/ztr.db')
print "Genes with pathways:", len(db._pathways)
print "Total pathway entries:", sum(len(v) for v in db._pathways.values())

test_gid = 'ztr:100381270'
if test_gid in db._pathways:
    print "Found", test_gid, "with", len(db._pathways[test_gid]), "pathways"
    print "Sample:", db._pathways[test_gid][:2]
else:
    print "NOT FOUND:", test_gid

pathways = list(db.pathways_from_gid(test_gid))
print "Method returned:", len(pathways), "pathways"
if pathways:
    print "First:", pathways[0]
EOFTEST

python test_preload.py > test_preload_output.txt 2>&1

# Show results
cat debug_db_stats.txt
echo "---"
cat test_preload_output.txt
```
