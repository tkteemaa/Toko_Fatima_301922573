-- ============================================================================
-- seed.sql — small hand-crafted seed for SplashPoint (Portfolio 1)
-- 4 pools, 8 lanes, 6 instructors, 6 guardians, 12 swimmers, 5 lesson types,
-- 6 sessions, ~10 enrolments, ~10 payments. Used for sanity-checking the
-- schema BEFORE the bulk generator runs.
-- ============================================================================

\set ON_ERROR_STOP on
BEGIN;

-- pools
INSERT INTO pool (name, city, address, opening_time, closing_time) VALUES
  ('SplashPoint Wuse',     'Abuja', '14 Adetokunbo Ademola Crescent, Wuse 2, Abuja',     '06:00:00', '20:00:00'),
  ('SplashPoint Maitama',  'Abuja', '20 IBB Way, Maitama, Abuja',                         '06:00:00', '20:00:00'),
  ('SplashPoint Ikoyi',    'Lagos', '8 Bank Road, Ikoyi, Lagos',                           '06:00:00', '20:00:00'),
  ('SplashPoint Lekki',    'Lagos', '12 Admiralty Way, Lekki Phase 1, Lagos',              '06:00:00', '20:00:00');

-- lanes (2 per pool)
INSERT INTO lane (pool_id, lane_number, max_capacity) VALUES
  (1, 1, 6), (1, 2, 6),
  (2, 1, 4), (2, 2, 4),
  (3, 1, 6), (3, 2, 6), (3, 3, 4),
  (4, 1, 6), (4, 2, 4);

-- instructors
INSERT INTO instructor (first_name, last_name, phone, email, hire_date, certification_level) VALUES
  ('Adaora',  'Bello',    '08031110001', 'adaora.bello@splashpoint.ng',   '2022-01-10', 'Level 4'),
  ('Musa',    'Ibrahim',  '08031110002', 'musa.ibrahim@splashpoint.ng',   '2021-06-15', 'Level 3'),
  ('Chioma',  'Eze',      '08031110003', 'chioma.eze@splashpoint.ng',     '2023-03-01', 'Level 2'),
  ('Tunde',   'Adeyemi',  '08031110004', 'tunde.adeyemi@splashpoint.ng',  '2020-09-12', 'Level 4'),
  ('Hauwa',   'Muhammed', '08031110005', 'hauwa.muhammed@splashpoint.ng', '2022-11-20', 'Level 3'),
  ('Emeka',   'Nwosu',    '08031110006', 'emeka.nwosu@splashpoint.ng',    '2024-02-05', 'Level 1');

-- guardians (for under-18 swimmers)
INSERT INTO guardian (first_name, last_name, phone, email, relationship) VALUES
  ('Ngozi',  'Okafor',   '08032220001', 'ngozi.okafor@gmail.com',   'Mother'),
  ('Kemi',   'Bello',    '08032220002', 'kemi.bello@gmail.com',     'Mother'),
  ('Ibrahim','Sani',     '08032220003', 'ibrahim.sani@gmail.com',   'Father'),
  ('Funke',  'Adeyemi',  '08032220004', 'funke.adeyemi@gmail.com',  'Mother'),
  ('Chidi',  'Eze',      '08032220005', 'chidi.eze@gmail.com',      'Father'),
  ('Zainab', 'Yusuf',    '08032220006', 'zainab.yusuf@gmail.com',   'Legal Guardian');

-- swimmers (mix of children, teens, adults)
INSERT INTO swimmer (first_name, last_name, dob, age_class, phone, email, guardian_id) VALUES
  ('Chika',   'Okafor',  '2018-03-12', 'Child',  NULL, NULL, 1),
  ('Tunde',   'Bello',   '2017-07-22', 'Child',  NULL, NULL, 2),
  ('Aisha',   'Sani',    '2014-11-05', 'Teen',   '08033330001', 'aisha.sani@gmail.com', 3),
  ('Ada',     'Eze',     '1995-01-15', 'Adult',  '08033330002', 'ada.eze@gmail.com',    NULL),
  ('Bola',    'Adeyemi', '1988-05-19', 'Adult',  '08033330003', 'bola.adeyemi@gmail.com',NULL),
  ('Yusuf',   'Yusuf',   '2012-08-30', 'Teen',   '08033330004', 'yusuf.yusuf@gmail.com',6),
  ('Fatima',  'Ali',     '1990-04-04', 'Adult',  '08033330005', 'fatima.ali@gmail.com', NULL),
  ('David',   'Ojo',     '2019-02-14', 'Child',  NULL, NULL, 4),
  ('Maryam',  'Bello',   '2015-09-09', 'Teen',   '08033330006', 'maryam.bello@gmail.com',2),
  ('John',    'Okon',    '1985-12-25', 'Adult',  '08033330007', 'john.okon@gmail.com',  NULL),
  ('Sandra',  'Nwosu',   '2011-06-18', 'Teen',   '08033330008', 'sandra.nwosu@gmail.com',5),
  ('Henry',   'Ibrahim', '2020-01-20', 'Child',  NULL, NULL, 1);

-- lesson types
INSERT INTO lesson_type (name, description, default_duration_min, is_group, capacity) VALUES
  ('Private 1-on-1',      'One swimmer, one instructor',                30, FALSE, 1),
  ('Group Children',      'Up to 6 children learning together',         45, TRUE,  6),
  ('Group Adult',         'Up to 4 adults learning together',           45, TRUE,  4),
  ('Adult Beginner',      'Up to 4 adults, no prior experience',        60, TRUE,  4),
  ('Toddler Splash',      'Up to 4 toddlers with guardian in water',    30, TRUE,  4);

-- sessions (today + tomorrow). Start times chosen so no lane or instructor overlaps.
-- We use NOW()-based offsets so the seed works whenever the student runs it.
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price) VALUES
  (3, 5, 1, 2, date_trunc('day', now()) + interval '9 hours',  date_trunc('day', now()) + interval '9 hours 45 minutes',  45, 5000.00),
  (3, 5, 1, 2, date_trunc('day', now()) + interval '10 hours', date_trunc('day', now()) + interval '10 hours 45 minutes', 45, 5000.00),
  (1, 1, 2, 1, date_trunc('day', now()) + interval '11 hours', date_trunc('day', now()) + interval '11 hours 30 minutes', 30, 8000.00),
  (1, 2, 3, 3, date_trunc('day', now()) + interval '12 hours', date_trunc('day', now()) + interval '12 hours 45 minutes', 45, 6000.00),
  (2, 3, 4, 4, date_trunc('day', now()) + interval '15 hours', date_trunc('day', now()) + interval '16 hours',           60, 7000.00),
  (4, 8, 5, 5, date_trunc('day', now()) + interval '16 hours', date_trunc('day', now()) + interval '16 hours 30 minutes', 30, 4000.00);

-- enrolments — fill some of the group sessions
INSERT INTO enrolment (session_id, swimmer_id, status) VALUES
  (1, 1, 'confirmed'),
  (1, 2, 'confirmed'),
  (2, 1, 'confirmed'),
  (2, 8, 'confirmed'),
  (3, 4, 'confirmed'),
  (4, 5, 'confirmed'),
  (5, 7, 'confirmed'),
  (6, 6, 'confirmed');

-- payments — one per enrolment
INSERT INTO payment (enrolment_id, amount, payment_method, status) VALUES
  (1, 5000.00, 'Card',         'paid'),
  (2, 5000.00, 'Bank Transfer','paid'),
  (3, 5000.00, 'Card',         'paid'),
  (4, 5000.00, 'USSD',         'paid'),
  (5, 8000.00, 'Cash',         'paid'),
  (6, 6000.00, 'Card',         'paid'),
  (7, 7000.00, 'POS',          'paid'),
  (8, 4000.00, 'Card',         'paid');

COMMIT;
