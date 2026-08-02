CREATE TABLE voting_sessions (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL,
  options_json TEXT NOT NULL CHECK(json_valid(options_json)),
  max_votes INTEGER NOT NULL CHECK(max_votes BETWEEN 1 AND 100),
  starts_at INTEGER NOT NULL,
  ends_at INTEGER NOT NULL,
  CHECK(starts_at < ends_at)
);
CREATE INDEX voting_sessions_room ON voting_sessions(room_id);

CREATE TABLE private_ballots (
  session_id TEXT NOT NULL REFERENCES voting_sessions(id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  choices_json TEXT NOT NULL CHECK(json_valid(choices_json)),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(session_id, uid)
) WITHOUT ROWID;

CREATE TABLE vote_totals (
  session_id TEXT NOT NULL REFERENCES voting_sessions(id) ON DELETE CASCADE,
  option_id TEXT NOT NULL,
  total INTEGER NOT NULL DEFAULT 0 CHECK(total >= 0),
  PRIMARY KEY(session_id, option_id)
) WITHOUT ROWID;

CREATE TABLE processed_mutations (
  session_id TEXT NOT NULL,
  uid TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  applied INTEGER NOT NULL DEFAULT 0 CHECK(applied IN (0, 1)),
  receipt_json TEXT,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(session_id, uid, mutation_id)
) WITHOUT ROWID;

CREATE TABLE membership_cache (
  room_id TEXT NOT NULL,
  uid TEXT NOT NULL,
  grant_expires_at INTEGER NOT NULL,
  checked_at INTEGER NOT NULL,
  PRIMARY KEY(room_id, uid)
) WITHOUT ROWID;
CREATE INDEX membership_cache_expiry ON membership_cache(grant_expires_at);
