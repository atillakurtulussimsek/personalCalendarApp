-- All timestamps are UTC. UUIDs are client-generated CHAR(36).

CREATE TABLE users (
  id            CHAR(36)     NOT NULL PRIMARY KEY,
  email         VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at    DATETIME(6)  NOT NULL,
  updated_at    DATETIME(6)  NOT NULL,
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE devices (
  id           CHAR(36)     NOT NULL PRIMARY KEY,
  user_id      CHAR(36)     NOT NULL,
  platform     VARCHAR(16)  NOT NULL,          -- android | macos | other
  name         VARCHAR(255) NOT NULL DEFAULT '',
  push_token   VARCHAR(512) NULL,
  last_sync_at DATETIME(6)  NULL,
  created_at   DATETIME(6)  NOT NULL,
  updated_at   DATETIME(6)  NOT NULL,
  deleted_at   DATETIME(6)  NULL,
  version      BIGINT       NOT NULL DEFAULT 1,
  KEY idx_devices_user (user_id),
  CONSTRAINT fk_devices_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Refresh-token sessions, one row per device login. Token is stored hashed (sha256 hex).
CREATE TABLE sessions (
  id                 CHAR(36)    NOT NULL PRIMARY KEY,
  user_id            CHAR(36)    NOT NULL,
  device_id          CHAR(36)    NULL,
  refresh_token_hash CHAR(64)    NOT NULL,
  expires_at         DATETIME(6) NOT NULL,
  created_at         DATETIME(6) NOT NULL,
  revoked_at         DATETIME(6) NULL,
  UNIQUE KEY uq_sessions_token (refresh_token_hash),
  KEY idx_sessions_user (user_id),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Single-row global sequence for sync ordering.
CREATE TABLE sync_counter (
  id    TINYINT NOT NULL PRIMARY KEY,
  value BIGINT  NOT NULL
) ENGINE=InnoDB;
INSERT INTO sync_counter (id, value) VALUES (1, 0);

CREATE TABLE calendars (
  id         CHAR(36)     NOT NULL PRIMARY KEY,
  user_id    CHAR(36)     NOT NULL,
  name       VARCHAR(255) NOT NULL,
  color      VARCHAR(16)  NOT NULL DEFAULT '#3B82F6',
  is_default BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at DATETIME(6)  NOT NULL,
  updated_at DATETIME(6)  NOT NULL,
  deleted_at DATETIME(6)  NULL,
  version    BIGINT       NOT NULL DEFAULT 1,
  server_seq BIGINT       NOT NULL,
  KEY idx_calendars_user_seq (user_id, server_seq),
  CONSTRAINT fk_calendars_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE events (
  id             CHAR(36)     NOT NULL PRIMARY KEY,
  user_id        CHAR(36)     NOT NULL,
  calendar_id    CHAR(36)     NOT NULL,
  title          VARCHAR(512) NOT NULL,
  description    TEXT         NOT NULL,
  location       VARCHAR(512) NOT NULL DEFAULT '',
  start_at       DATETIME(6)  NOT NULL,            -- UTC
  end_at         DATETIME(6)  NOT NULL,            -- UTC
  timezone       VARCHAR(64)  NOT NULL,            -- IANA, e.g. Europe/Istanbul
  all_day        BOOLEAN      NOT NULL DEFAULT FALSE,
  rrule          TEXT         NULL,                -- RFC 5545 RRULE string (without "RRULE:" prefix)
  recurrence_id  CHAR(36)     NULL,                -- parent series id for exception instances
  original_start DATETIME(6)  NULL,                -- the occurrence this exception replaces (UTC)
  reminders      JSON         NOT NULL,            -- [minutes_before, ...]
  created_at     DATETIME(6)  NOT NULL,
  updated_at     DATETIME(6)  NOT NULL,
  deleted_at     DATETIME(6)  NULL,
  version        BIGINT       NOT NULL DEFAULT 1,
  server_seq     BIGINT       NOT NULL,
  KEY idx_events_user_seq (user_id, server_seq),
  KEY idx_events_user_range (user_id, start_at, end_at),
  KEY idx_events_recurrence (recurrence_id),
  CONSTRAINT fk_events_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE notes (
  id         CHAR(36)     NOT NULL PRIMARY KEY,
  user_id    CHAR(36)     NOT NULL,
  title      VARCHAR(512) NOT NULL,
  body       MEDIUMTEXT   NOT NULL,                -- Markdown
  pinned     BOOLEAN      NOT NULL DEFAULT FALSE,
  event_id   CHAR(36)     NULL,
  tags       JSON         NOT NULL,                -- ["tag", ...]
  created_at DATETIME(6)  NOT NULL,
  updated_at DATETIME(6)  NOT NULL,
  deleted_at DATETIME(6)  NULL,
  version    BIGINT       NOT NULL DEFAULT 1,
  server_seq BIGINT       NOT NULL,
  KEY idx_notes_user_seq (user_id, server_seq),
  KEY idx_notes_event (event_id),
  FULLTEXT KEY ft_notes_title_body (title, body),
  CONSTRAINT fk_notes_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
