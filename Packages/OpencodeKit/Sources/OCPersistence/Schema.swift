import GRDB

extension PersistenceWriter {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE server(id TEXT PRIMARY KEY NOT NULL,json BLOB NOT NULL);
                CREATE TABLE project(server_id TEXT NOT NULL,id TEXT NOT NULL,active_at REAL,json BLOB NOT NULL,PRIMARY KEY(server_id,id));
                CREATE TABLE session(server_id TEXT NOT NULL,id TEXT NOT NULL,parent_id TEXT,project_id TEXT,directory TEXT,title TEXT,
                    updated_at REAL,idle_at REAL,viewed_at REAL,outcome TEXT,json BLOB NOT NULL,accessed_at REAL NOT NULL,PRIMARY KEY(server_id,id));
                CREATE INDEX session_recent ON session(server_id,updated_at DESC);
                CREATE INDEX session_parent ON session(server_id,parent_id);
                CREATE INDEX session_lru ON session(accessed_at);
                CREATE TABLE message(server_id TEXT NOT NULL,session_id TEXT NOT NULL,id TEXT NOT NULL,position INTEGER NOT NULL,
                    type TEXT,complete INTEGER,json BLOB NOT NULL,PRIMARY KEY(server_id,session_id,id));
                CREATE INDEX message_order ON message(server_id,session_id,position);
                CREATE TABLE transcript_window(server_id TEXT NOT NULL,session_id TEXT NOT NULL,older_cursor TEXT,fetched_at REAL,PRIMARY KEY(server_id,session_id));
                CREATE TABLE catalog(server_id TEXT NOT NULL,location_key TEXT NOT NULL,kind TEXT NOT NULL,fetched_at REAL,json BLOB NOT NULL,PRIMARY KEY(server_id,location_key,kind));
                CREATE TABLE draft(id TEXT PRIMARY KEY NOT NULL,server_id TEXT NOT NULL,session_id TEXT,directory TEXT,text BLOB NOT NULL,attachments_json BLOB NOT NULL,delivery TEXT NOT NULL,updated_at REAL NOT NULL);
                CREATE UNIQUE INDEX draft_session ON draft(server_id,session_id) WHERE session_id IS NOT NULL;
                CREATE UNIQUE INDEX draft_directory ON draft(server_id,directory) WHERE session_id IS NULL;
                CREATE TABLE outbox(id TEXT PRIMARY KEY NOT NULL,server_id TEXT NOT NULL,session_id TEXT NOT NULL,prelude BLOB NOT NULL,body BLOB NOT NULL,created_at REAL NOT NULL,attempts INTEGER NOT NULL,state TEXT NOT NULL);
                CREATE INDEX outbox_session ON outbox(server_id,session_id,created_at);
                CREATE TABLE pty_cursor(server_id TEXT NOT NULL,pty_id TEXT NOT NULL,cursor INTEGER NOT NULL,PRIMARY KEY(server_id,pty_id));
                CREATE TABLE local_meta(server_id TEXT NOT NULL,session_id TEXT NOT NULL,pinned INTEGER NOT NULL DEFAULT 0,hidden INTEGER NOT NULL DEFAULT 0,muted INTEGER NOT NULL DEFAULT 0,reviewed_files BLOB,PRIMARY KEY(server_id,session_id));
                CREATE TABLE openapi_ops(version TEXT PRIMARY KEY NOT NULL,ops BLOB NOT NULL);
                CREATE TABLE cache_migration(key TEXT PRIMARY KEY NOT NULL);
                """)
        }
        migrator.registerMigration("v2-outbox-operation") { db in
            try db.execute(sql: "ALTER TABLE outbox ADD COLUMN operation TEXT NOT NULL DEFAULT 'prompt'")
        }
        migrator.registerMigration("v3-composer-draft") { db in
            try db.execute(sql: "ALTER TABLE draft ADD COLUMN options_json BLOB NOT NULL DEFAULT x'7b227368656c6c223a66616c73657d'")
        }
        migrator.registerMigration("v4-review") { db in
            try db.execute(sql: "ALTER TABLE draft ADD COLUMN comments_json BLOB NOT NULL DEFAULT x'5b5d'")
            try db.execute(sql: "ALTER TABLE local_meta ADD COLUMN review_state BLOB")
        }
        migrator.registerMigration("v5-notification-replies") { db in
            try db.execute(sql: "CREATE TABLE notification_reply(server_id TEXT NOT NULL,notification_id TEXT NOT NULL,input_id TEXT NOT NULL,PRIMARY KEY(server_id,notification_id))")
        }
        // A terminal's resume point: the cursor, the screen it matches (escape sequences) and its size.
        migrator.registerMigration("v6-terminal-resume") { db in
            for column in ["directory TEXT", "cols INTEGER", "rows INTEGER", "screen BLOB", "updated_at REAL"] {
                try db.execute(sql: "ALTER TABLE pty_cursor ADD COLUMN " + column)
            }
        }
        // Set when the app saw the process exit with every byte received, so a relaunch shows no gap.
        migrator.registerMigration("v7-terminal-exited-live") { db in
            try db.execute(sql: "ALTER TABLE pty_cursor ADD COLUMN exited_live INTEGER")
        }
        return migrator
    }
}
