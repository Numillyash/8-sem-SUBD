\pset pager off
\timing on

SET search_path = lab4, public;
SET jit = off;
SET max_parallel_workers_per_gather = 0;
SET enable_partition_pruning = on;

\echo '=== PURE SCAN Q1: plain table, no aggregate ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT 1
FROM lab4.orders_plain
WHERE order_date >= DATE '2024-01-01'
  AND order_date <  DATE '2024-04-01';

\echo '=== PURE SCAN Q1: partitioned table, no aggregate ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT 1
FROM lab4.orders_partitioned
WHERE order_date >= DATE '2024-01-01'
  AND order_date <  DATE '2024-04-01';

\echo '=== PURE SCAN Q2: plain table, no aggregate ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT 1
FROM lab4.orders_plain
WHERE order_date >= DATE '2024-04-01'
  AND order_date <  DATE '2024-07-01';

\echo '=== PURE SCAN Q2: partitioned table, no aggregate ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT 1
FROM lab4.orders_partitioned
WHERE order_date >= DATE '2024-04-01'
  AND order_date <  DATE '2024-07-01';

\echo '=== PURE SCAN Q1+Q2: plain table, no aggregate ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT 1
FROM lab4.orders_plain
WHERE order_date >= DATE '2024-01-01'
  AND order_date <  DATE '2024-07-01';

\echo '=== PURE SCAN Q1+Q2: partitioned table, no aggregate ==='
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT 1
FROM lab4.orders_partitioned
WHERE order_date >= DATE '2024-01-01'
  AND order_date <  DATE '2024-07-01';

\echo '=== PURE SCAN DONE ==='
