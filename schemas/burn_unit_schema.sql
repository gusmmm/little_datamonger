-- Initial schema for the burn unit database

-- Table: patients
CREATE TABLE IF NOT EXISTS patients (
    id SERIAL PRIMARY KEY,
    numero_processo VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender VARCHAR(50),
    address VARCHAR(255),
    postal_code VARCHAR(20),
    location VARCHAR(100),
    phone_number VARCHAR(20),
    email VARCHAR(255),
    observations TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
