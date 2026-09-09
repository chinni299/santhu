-- DuoChat Production Database Schema

CREATE SEQUENCE IF NOT EXISTS users_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS conversations_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS conversation_members_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS messages_id_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  fcm_token TEXT,
  last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  public_key TEXT,
  is_online BOOLEAN DEFAULT false,
  avatar_url TEXT,
  status TEXT DEFAULT 'Available'
);

CREATE TABLE IF NOT EXISTS conversations (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conversation_members (
  id SERIAL PRIMARY KEY,
  conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id SERIAL PRIMARY KEY,
  conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  is_read BOOLEAN DEFAULT false,
  is_delivered BOOLEAN DEFAULT false,
  is_edited BOOLEAN DEFAULT false,
  is_deleted BOOLEAN DEFAULT false,
  attachment_url TEXT,
  attachment_type VARCHAR(50),
  attachment_name TEXT,
  attachment_size INTEGER,
  reply_to_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
  reactions JSONB DEFAULT '{}'::jsonb,
  nonce TEXT,
  is_encrypted BOOLEAN DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user ON conversation_members(user_id);
CREATE INDEX IF NOT EXISTS idx_conversation_members_conv ON conversation_members(conversation_id);
