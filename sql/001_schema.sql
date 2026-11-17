CREATE TABLE IF NOT EXISTS inference_history (
  id SERIAL PRIMARY KEY,
  user_sub TEXT NOT NULL,
  input JSONB NOT NULL,
  prediction INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
