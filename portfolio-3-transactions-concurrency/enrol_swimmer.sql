-- ============================================================================
-- enrol_swimmer.sql — atomic enrolment + payment transaction (Portfolio 3)
-- Defines the function enrol_swimmer(p_session_id, p_swimmer_id, p_method).
-- Returns the new enrolment_id on success.
-- Raises an exception (and rolls back) on any failure.
-- ============================================================================

\set ON_ERROR_STOP on

DROP FUNCTION IF EXISTS enrol_swimmer(INTEGER, INTEGER, TEXT);

CREATE OR REPLACE FUNCTION enrol_swimmer(
    p_session_id  INTEGER,
    p_swimmer_id  INTEGER,
    p_method      TEXT DEFAULT 'Card'
) RETURNS INTEGER AS $$
DECLARE
    v_enrolment_id  INTEGER;
    v_payment_id    INTEGER;
    v_capacity      INTEGER;
    v_is_group      BOOLEAN;
    v_current       INTEGER;
    v_price         NUMERIC(10,2);
    v_swimmer_name  TEXT;
    v_already       INTEGER;
BEGIN
    -- 1. Validate swimmer exists
    SELECT first_name || ' ' || last_name INTO v_swimmer_name
      FROM swimmer WHERE swimmer_id = p_swimmer_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Swimmer % does not exist', p_swimmer_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- 2. Lock the session row FOR UPDATE so concurrent callers block here
    --    (this is the FOR UPDATE fix; see race_condition_guide.md)
    SELECT lt.capacity, lt.is_group, ls.price
      INTO v_capacity, v_is_group, v_price
      FROM lesson_session ls
      JOIN lesson_type lt ON lt.lesson_type_id = ls.lesson_type_id
     WHERE ls.session_id = p_session_id
     FOR UPDATE OF ls;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- 3. Check the swimmer isn't already enrolled (idempotency)
    SELECT count(*) INTO v_already FROM enrolment
     WHERE session_id = p_session_id AND swimmer_id = p_swimmer_id;
    IF v_already > 0 THEN
        RAISE EXCEPTION 'Swimmer % is already enrolled in session %',
            v_swimmer_name, p_session_id
            USING ERRCODE = 'unique_violation';
    END IF;

    -- 4. Check capacity (re-read AFTER the FOR UPDATE lock to avoid the race)
    SELECT count(*) INTO v_current FROM enrolment
     WHERE session_id = p_session_id
       AND status IN ('confirmed','attended');
    IF v_current + 1 > v_capacity THEN
        RAISE EXCEPTION 'Session % is full (capacity=%, already enrolled=%)',
            p_session_id, v_capacity, v_current
            USING ERRCODE = 'check_violation';
    END IF;

    -- 5. Insert the enrolment (the trg_group_capacity trigger will also fire)
    INSERT INTO enrolment (session_id, swimmer_id, status)
    VALUES (p_session_id, p_swimmer_id, 'confirmed')
    RETURNING enrolment_id INTO v_enrolment_id;

    -- 6. Record the payment. If the payment fails for any reason
    --    (e.g. amount <= 0, or a simulated card-decline), the exception
    --    unwinds the entire transaction — the enrolment row disappears too.
    BEGIN
        INSERT INTO payment (enrolment_id, amount, payment_method, status)
        VALUES (v_enrolment_id, v_price, p_method, 'paid');
    EXCEPTION WHEN check_violation THEN
        RAISE EXCEPTION 'Payment failed for enrolment %: %', v_enrolment_id, SQLERRM
            USING ERRCODE = 'check_violation';
    END;

    RETURN v_enrolment_id;
END;
$$ LANGUAGE plpgsql;

\echo 'Function enrol_swimmer(integer, integer, text) created.'
\echo 'Usage:  SELECT enrol_swimmer(<session_id>, <swimmer_id>, ''Card'');'
\echo 'The function runs inside a transaction; COMMIT or ROLLBACK afterwards.'
