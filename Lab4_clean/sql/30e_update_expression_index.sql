\pset pager off
\timing on

SET client_min_messages TO notice;

\echo '=== 30e UPDATE expression_index: math expression lookup_only vs lookup_and_update ==='

DO $$
DECLARE
    v_sizes bigint[] := ARRAY[
        5000, 10000, 25000, 50000, 100000, 250000, 500000,
        1000000, 2000000
    ];
    v_rows bigint;
    v_run integer;
    v_from bigint;
    v_to bigint;
    v_expr text := '((customer_id::bigint * 1000000::bigint) + amount_cents::bigint)';
BEGIN
    FOREACH v_rows IN ARRAY v_sizes LOOP
        RAISE NOTICE 'expression_index size %', v_rows;

        PERFORM lab4.prepare_update_index_usage_work(v_rows);

        CREATE INDEX idx_30_update_expression_math
        ON lab4.update_index_usage_work
        (((customer_id::bigint * 1000000::bigint) + amount_cents::bigint));

        ANALYZE lab4.update_index_usage_work;

        PERFORM lab4.save_update_index_usage_explain
        (
            'expression_index',
            'lookup_only',
            v_rows,
            'update_marker = update_marker + 1',
            v_expr || ' BETWEEN $1 AND $2',
            v_rows - 999,
            v_rows
        );

        PERFORM lab4.save_update_index_usage_explain
        (
            'expression_index',
            'lookup_and_update',
            v_rows,
            'amount_cents = amount_cents + 1000000000',
            v_expr || ' BETWEEN $1 AND $2',
            v_rows - 999,
            v_rows
        );

        -- Режим 1: expression index используется в WHERE, но customer_id/amount_cents не меняются.
        FOR v_run IN 1..5 LOOP
            v_to := v_rows - ((v_run - 1) * 1000);
            v_from := v_to - 999;

            PERFORM lab4.measure_update_index_usage
            (
                'expression_index',
                'lookup_only',
                v_rows,
                v_run,
                'update_marker = update_marker + 1',
                v_expr || ' BETWEEN $1 AND $2',
                v_from,
                v_to
            );
        END LOOP;

        -- Режим 2: expression index используется в WHERE, и UPDATE меняет amount_cents.
        FOR v_run IN 1..5 LOOP
            v_to := v_rows - ((v_run - 1) * 1000);
            v_from := v_to - 999;

            PERFORM lab4.measure_update_index_usage
            (
                'expression_index',
                'lookup_and_update',
                v_rows,
                v_run,
                'amount_cents = amount_cents + 1000000000',
                v_expr || ' BETWEEN $1 AND $2',
                v_from,
                v_to
            );
        END LOOP;
    END LOOP;
END;
$$;

\echo '=== 30e expression_index done ==='
