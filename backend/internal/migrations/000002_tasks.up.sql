CREATE TABLE tasks (
  id         CHAR(36)     NOT NULL PRIMARY KEY,
  user_id    CHAR(36)     NOT NULL,
  title      VARCHAR(512) NOT NULL,
  due_at     DATETIME(6)  NULL,                 -- UTC
  done       BOOLEAN      NOT NULL DEFAULT FALSE,
  note_id    CHAR(36)     NULL,
  created_at DATETIME(6)  NOT NULL,
  updated_at DATETIME(6)  NOT NULL,
  deleted_at DATETIME(6)  NULL,
  version    BIGINT       NOT NULL DEFAULT 1,
  server_seq BIGINT       NOT NULL,
  KEY idx_tasks_user_seq (user_id, server_seq),
  KEY idx_tasks_user_due (user_id, done, due_at),
  CONSTRAINT fk_tasks_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
