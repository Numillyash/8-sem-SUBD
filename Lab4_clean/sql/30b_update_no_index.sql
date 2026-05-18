\pset pager off
\timing on

SET client_min_messages TO notice;

\echo '=== 30b UPDATE no_index: real Seq Scan search ==='

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
        RAISE NOTICE 'no_index size %', v_rows;

        PERFORM lab4.prepare_update_index_usage_work(v_rows);

        -- Индекса по search_key нет. WHERE должен идти через Seq Scan.
        PERFORM lab4.save_update_index_usage_explain
        (
            'no_index',
            'no_index',
            v_rows,
            'update_marker = update_marker + 1',
            'search_key BETWEEN $1 AND $2',
            v_rows - 999,
            v_rows
        );

        FOR v_run IN 1..5 LOOP
            v_to := v_rows - ((v_run - 1) * 1000);
            v_from := v_to - 999;

            PERFORM lab4.measure_update_index_usage
            (
                'no_index',
                'no_index',
                v_rows,
                v_run,
                'update_marker = update_marker + 1',
                'search_key BETWEEN $1 AND $2',
                v_from,
                v_to
            );
        END LOOP;
    END LOOP;
END;
$$;

\echo '=== 30b no_index done ==='
