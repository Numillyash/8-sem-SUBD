\pset pager off
\timing on

SET client_min_messages TO notice;

\echo '=== 30c UPDATE simple_btree: lookup_only vs lookup_and_update ==='

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
BEGIN
    FOREACH v_rows IN ARRAY v_sizes LOOP
        RAISE NOTICE 'simple_btree size %', v_rows;

        PERFORM lab4.prepare_update_index_usage_work(v_rows);

        CREATE INDEX idx_30_update_simple_btree
        ON lab4.update_index_usage_work(simple_key);

        ANALYZE lab4.update_index_usage_work;

        PERFORM lab4.save_update_index_usage_explain
        (
            'simple_btree',
            'lookup_only',
            v_rows,
            'update_marker = update_marker + 1',
            'simple_key BETWEEN $1 AND $2',
            v_rows - 999,
            v_rows
        );

        PERFORM lab4.save_update_index_usage_explain
        (
            'simple_btree',
            'lookup_and_update',
            v_rows,
            'simple_key = simple_key + 1000000000000::bigint',
            'simple_key BETWEEN $1 AND $2',
            v_rows - 999,
            v_rows
        );

        -- Режим 1: индекс участвует в WHERE, но индексируемое поле simple_key не меняется.
        FOR v_run IN 1..5 LOOP
            v_to := v_rows - ((v_run - 1) * 1000);
            v_from := v_to - 999;

            PERFORM lab4.measure_update_index_usage
            (
                'simple_btree',
                'lookup_only',
                v_rows,
                v_run,
                'update_marker = update_marker + 1',
                'simple_key BETWEEN $1 AND $2',
                v_from,
                v_to
            );
        END LOOP;

        -- Режим 2: индекс участвует в WHERE, и UPDATE меняет simple_key.
        FOR v_run IN 1..5 LOOP
            v_to := v_rows - ((v_run - 1) * 1000);
            v_from := v_to - 999;

            PERFORM lab4.measure_update_index_usage
            (
                'simple_btree',
                'lookup_and_update',
                v_rows,
                v_run,
                'simple_key = simple_key + 1000000000000::bigint',
                'simple_key BETWEEN $1 AND $2',
                v_from,
                v_to
            );
        END LOOP;
    END LOOP;
END;
$$;

\echo '=== 30c simple_btree done ==='
