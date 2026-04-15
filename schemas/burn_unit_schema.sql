-- Initial schema for the burn unit database

-- Gender enum used by patients.gender
DO $$
DECLARE
    fk_rec RECORD;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'patient_gender'
    ) THEN
        CREATE TYPE patient_gender AS ENUM ('M', 'F', 'Other');
    END IF;
END
$$;

-- Table: patients
CREATE TABLE IF NOT EXISTS patients (
    id SERIAL PRIMARY KEY,
    numero_processo VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender patient_gender,
    address VARCHAR(255),
    postal_code VARCHAR(20),
    location VARCHAR(100),
    phone_number VARCHAR(20),
    email VARCHAR(255),
    observations TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Ensure existing databases also use the enum on patients.gender.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'patients'
          AND column_name = 'gender'
          AND udt_name <> 'patient_gender'
    ) THEN
        ALTER TABLE patients
        ALTER COLUMN gender TYPE patient_gender
        USING CASE
            WHEN gender IN ('M', 'F', 'Other') THEN gender::patient_gender
            WHEN gender IS NULL OR btrim(gender) = '' THEN NULL
            ELSE 'Other'::patient_gender
        END;
    END IF;
END
$$;

-- Keep last_updated in sync whenever a row changes.
CREATE OR REPLACE FUNCTION set_row_last_updated()
RETURNS TRIGGER AS $$
BEGIN
    IF (to_jsonb(NEW) - 'last_updated') IS DISTINCT FROM (to_jsonb(OLD) - 'last_updated') THEN
        NEW.last_updated = clock_timestamp();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach one update trigger per table that has a last_updated column.
DO $$
DECLARE
    rec RECORD;
    trigger_name TEXT;
BEGIN
    FOR rec IN
        SELECT c.table_schema, c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema
         AND t.table_name = c.table_name
        WHERE c.column_name = 'last_updated'
          AND c.table_schema = 'public'
          AND t.table_type = 'BASE TABLE'
    LOOP
        trigger_name := format('trg_%s_last_updated', rec.table_name);

        EXECUTE format(
            'DROP TRIGGER IF EXISTS %I ON %I.%I',
            trigger_name,
            rec.table_schema,
            rec.table_name
        );

        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION set_row_last_updated()',
            trigger_name,
            rec.table_schema,
            rec.table_name
        );
    END LOOP;
END
$$;

CREATE TABLE IF NOT EXISTS locations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    type_of_location VARCHAR(100),
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS burn_unit_admissions (
    id SERIAL PRIMARY KEY,
    admission_id VARCHAR(255) NOT NULL UNIQUE,
    patient_id INTEGER REFERENCES patients(id) ON DELETE SET NULL,
    admission_date DATE NOT NULL,
    discharge_date DATE,
    admission_from INTEGER REFERENCES locations(id) ON DELETE SET NULL,
    discharge_to INTEGER REFERENCES locations(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Keep admissions as orphans when a patient is deleted.
DO $$
DECLARE
    existing_fk_name TEXT;
BEGIN
    ALTER TABLE burn_unit_admissions
    ALTER COLUMN patient_id DROP NOT NULL;

    SELECT c.conname
    INTO existing_fk_name
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(c.conkey)
    WHERE c.contype = 'f'
      AND n.nspname = 'public'
      AND t.relname = 'burn_unit_admissions'
      AND a.attname = 'patient_id'
    LIMIT 1;

    IF existing_fk_name IS NOT NULL THEN
        EXECUTE format(
            'ALTER TABLE public.burn_unit_admissions DROP CONSTRAINT %I',
            existing_fk_name
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_burn_unit_admissions_patient'
    ) THEN
        ALTER TABLE burn_unit_admissions
        ADD CONSTRAINT fk_burn_unit_admissions_patient
        FOREIGN KEY (patient_id)
        REFERENCES patients(id)
        ON DELETE SET NULL;
    END IF;
END
$$;

-- Convert legacy text values into location references and enforce FK constraints.
DO $$
DECLARE
    fk_rec RECORD;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'burn_unit_admissions'
          AND column_name = 'admission_from'
          AND udt_name <> 'int4'
    ) THEN
        INSERT INTO locations (name, type_of_location, description)
        SELECT DISTINCT btrim(src.value), 'legacy', 'Imported from legacy admission_from/discharge_to text values'
        FROM (
            SELECT admission_from AS value
            FROM burn_unit_admissions
            UNION ALL
            SELECT discharge_to AS value
            FROM burn_unit_admissions
        ) src
        WHERE src.value IS NOT NULL
          AND btrim(src.value) <> ''
          AND NOT EXISTS (
                SELECT 1
                FROM locations l
                WHERE lower(l.name) = lower(btrim(src.value))
          );

        ALTER TABLE burn_unit_admissions
        ALTER COLUMN admission_from TYPE INTEGER
        USING CASE
            WHEN admission_from IS NULL OR btrim(admission_from) = '' THEN NULL
            WHEN admission_from ~ '^[0-9]+$' THEN admission_from::INTEGER
            ELSE (
                SELECT l.id
                FROM locations l
                WHERE lower(l.name) = lower(btrim(admission_from))
                ORDER BY l.id
                LIMIT 1
            )
        END;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'burn_unit_admissions'
          AND column_name = 'discharge_to'
          AND udt_name <> 'int4'
    ) THEN
        ALTER TABLE burn_unit_admissions
        ALTER COLUMN discharge_to TYPE INTEGER
        USING CASE
            WHEN discharge_to IS NULL OR btrim(discharge_to) = '' THEN NULL
            WHEN discharge_to ~ '^[0-9]+$' THEN discharge_to::INTEGER
            ELSE (
                SELECT l.id
                FROM locations l
                WHERE lower(l.name) = lower(btrim(discharge_to))
                ORDER BY l.id
                LIMIT 1
            )
        END;
    END IF;

    FOR fk_rec IN
        SELECT c.conname
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(c.conkey)
        WHERE c.contype = 'f'
          AND n.nspname = 'public'
          AND t.relname = 'burn_unit_admissions'
          AND a.attname = 'admission_from'
    LOOP
        EXECUTE format(
            'ALTER TABLE public.burn_unit_admissions DROP CONSTRAINT %I',
            fk_rec.conname
        );
    END LOOP;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_burn_unit_admissions_admission_from_location'
    ) THEN
        ALTER TABLE burn_unit_admissions
        ADD CONSTRAINT fk_burn_unit_admissions_admission_from_location
        FOREIGN KEY (admission_from)
        REFERENCES locations(id)
        ON DELETE SET NULL;
    END IF;

    FOR fk_rec IN
        SELECT c.conname
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(c.conkey)
        WHERE c.contype = 'f'
          AND n.nspname = 'public'
          AND t.relname = 'burn_unit_admissions'
          AND a.attname = 'discharge_to'
    LOOP
        EXECUTE format(
            'ALTER TABLE public.burn_unit_admissions DROP CONSTRAINT %I',
            fk_rec.conname
        );
    END LOOP;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_burn_unit_admissions_discharge_to_location'
    ) THEN
        ALTER TABLE burn_unit_admissions
        ADD CONSTRAINT fk_burn_unit_admissions_discharge_to_location
        FOREIGN KEY (discharge_to)
        REFERENCES locations(id)
        ON DELETE SET NULL;
    END IF;
END
$$;

-- Re-attach update triggers after all table declarations and migrations.
DO $$
DECLARE
    rec RECORD;
    trigger_name TEXT;
BEGIN
    FOR rec IN
        SELECT c.table_schema, c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema
         AND t.table_name = c.table_name
        WHERE c.column_name = 'last_updated'
          AND c.table_schema = 'public'
          AND t.table_type = 'BASE TABLE'
    LOOP
        trigger_name := format('trg_%s_last_updated', rec.table_name);

        EXECUTE format(
            'DROP TRIGGER IF EXISTS %I ON %I.%I',
            trigger_name,
            rec.table_schema,
            rec.table_name
        );

        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION set_row_last_updated()',
            trigger_name,
            rec.table_schema,
            rec.table_name
        );
    END LOOP;
END
$$;