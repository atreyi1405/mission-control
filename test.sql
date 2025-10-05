-- Mission Control Pathway Tracker - Database Schema
-- PostgreSQL / MySQL compatible

-- Clients table
CREATE TABLE clients (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Programmes table
CREATE TABLE programmes (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Cohorts table (links clients to programmes)
CREATE TABLE cohorts (
    id SERIAL PRIMARY KEY,
    client_id INTEGER REFERENCES clients(id) ON DELETE CASCADE,
    programme_id INTEGER REFERENCES programmes(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    start_date DATE,
    end_date DATE,
    status VARCHAR(50) DEFAULT 'Active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(client_id, programme_id, name)
);

-- Modules table
CREATE TABLE modules (
    id SERIAL PRIMARY KEY,
    programme_id INTEGER REFERENCES programmes(id) ON DELETE CASCADE,
    module_number VARCHAR(50),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Classes within modules
CREATE TABLE classes (
    id SERIAL PRIMARY KEY,
    module_id INTEGER REFERENCES modules(id) ON DELETE CASCADE,
    class_number VARCHAR(50),
    name VARCHAR(255) NOT NULL,
    type VARCHAR(100) DEFAULT 'Slide Deck',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Version tracking for content
CREATE TABLE content_versions (
    id SERIAL PRIMARY KEY,
    version_code VARCHAR(50) NOT NULL UNIQUE, -- ID-001, ID-002, etc.
    cohort_id INTEGER REFERENCES cohorts(id) ON DELETE CASCADE,
    module_id INTEGER REFERENCES modules(id) ON DELETE CASCADE,
    version_number VARCHAR(50) NOT NULL, -- v1.0, v1.5, v2.0
    parent_version_id INTEGER REFERENCES content_versions(id), -- References previous version
    delivery_method VARCHAR(50) DEFAULT 'Virtual',
    status VARCHAR(50) DEFAULT 'Not Started', -- Not Started, Customization, Review, Ready
    created_by VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

-- Individual content files within a version
CREATE TABLE content_files (
    id SERIAL PRIMARY KEY,
    content_version_id INTEGER REFERENCES content_versions(id) ON DELETE CASCADE,
    class_id INTEGER REFERENCES classes(id) ON DELETE CASCADE,
    file_path VARCHAR(500),
    file_name VARCHAR(255),
    file_type VARCHAR(100),
    is_modified BOOLEAN DEFAULT false, -- True if this file changed from parent version
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Change history - tracks what changed between versions
CREATE TABLE version_changes (
    id SERIAL PRIMARY KEY,
    content_version_id INTEGER REFERENCES content_versions(id) ON DELETE CASCADE,
    class_id INTEGER REFERENCES classes(id) ON DELETE CASCADE,
    change_type VARCHAR(50), -- 'Modified', 'Added', 'Removed'
    change_description TEXT,
    changed_by VARCHAR(255),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Cohort-Module assignments (tracks which modules each cohort is taking)
CREATE TABLE cohort_modules (
    id SERIAL PRIMARY KEY,
    cohort_id INTEGER REFERENCES cohorts(id) ON DELETE CASCADE,
    module_id INTEGER REFERENCES modules(id) ON DELETE CASCADE,
    current_version_id INTEGER REFERENCES content_versions(id),
    status VARCHAR(50) DEFAULT 'Not Started',
    assigned_date DATE DEFAULT CURRENT_DATE,
    completion_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(cohort_id, module_id)
);

-- Integration tracking (for Monday.com, Google Drive, etc.)
CREATE TABLE integration_logs (
    id SERIAL PRIMARY KEY,
    integration_source VARCHAR(100), -- 'Monday.com', 'Google Drive', etc.
    entity_type VARCHAR(100), -- 'cohort', 'content_version', etc.
    entity_id INTEGER,
    action VARCHAR(100), -- 'created', 'updated', 'synced'
    external_id VARCHAR(255), -- ID from external system
    sync_status VARCHAR(50) DEFAULT 'success',
    error_message TEXT,
    synced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Users table (for access control)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255),
    role VARCHAR(50) DEFAULT 'viewer', -- 'admin', 'editor', 'viewer'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_cohorts_client ON cohorts(client_id);
CREATE INDEX idx_cohorts_programme ON cohorts(programme_id);
CREATE INDEX idx_modules_programme ON modules(programme_id);
CREATE INDEX idx_classes_module ON classes(module_id);
CREATE INDEX idx_content_versions_cohort ON content_versions(cohort_id);
CREATE INDEX idx_content_versions_module ON content_versions(module_id);
CREATE INDEX idx_content_files_version ON content_files(content_version_id);
CREATE INDEX idx_cohort_modules_cohort ON cohort_modules(cohort_id);
CREATE INDEX idx_cohort_modules_module ON cohort_modules(module_id);
CREATE INDEX idx_integration_logs_entity ON integration_logs(entity_type, entity_id);

-- Sample queries for common use cases:

-- 1. Get all modules for a specific client and cohort with current versions
/*
SELECT 
    c.name as client_name,
    co.name as cohort_name,
    m.name as module_name,
    cv.version_number,
    cv.version_code,
    cm.status,
    cv.delivery_method
FROM clients c
JOIN cohorts co ON co.client_id = c.id
JOIN cohort_modules cm ON cm.cohort_id = co.id
JOIN modules m ON m.id = cm.module_id
LEFT JOIN content_versions cv ON cv.id = cm.current_version_id
WHERE c.name = 'Aer Lingus' AND co.name = 'Cohort 1';
*/

-- 2. Get what changed in a specific version compared to parent
/*
SELECT 
    vc.change_type,
    cl.name as class_name,
    vc.change_description,
    vc.changed_by,
    vc.changed_at
FROM version_changes vc
JOIN classes cl ON cl.id = vc.class_id
WHERE vc.content_version_id = 2
ORDER BY vc.changed_at DESC;
*/

-- 3. Get all content for a version (including inherited from parent)
/*
SELECT 
    cl.class_number,
    cl.name as class_name,
    cf.file_name,
    cf.is_modified,
    cv.version_code
FROM content_versions cv
LEFT JOIN content_files cf ON cf.content_version_id = cv.id
LEFT JOIN classes cl ON cl.id = cf.class_id
WHERE cv.version_code = 'ID-002'
UNION
SELECT 
    cl.class_number,
    cl.name as class_name,
    cf.file_name,
    false as is_modified,
    parent_cv.version_code
FROM content_versions cv
JOIN content_versions parent_cv ON cv.parent_version_id = parent_cv.id
JOIN content_files cf ON cf.content_version_id = parent_cv.id
JOIN classes cl ON cl.id = cf.class_id
WHERE cv.version_code = 'ID-002'
  AND cl.id NOT IN (
    SELECT class_id FROM content_files 
    WHERE content_version_id = cv.id
  );
*/

-- 4. Get latest version for each cohort-module combination
/*
SELECT 
    c.name as client_name,
    co.name as cohort_name,
    m.name as module_name,
    cv.version_code,
    cv.version_number,
    cv.status,
    cv.updated_at
FROM cohort_modules cm
JOIN cohorts co ON co.id = cm.cohort_id
JOIN clients c ON c.id = co.client_id
JOIN modules m ON m.id = cm.module_id
JOIN content_versions cv ON cv.id = cm.current_version_id
ORDER BY cv.updated_at DESC;
*/