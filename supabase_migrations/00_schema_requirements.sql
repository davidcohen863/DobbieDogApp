-- =====================================================
-- DATABASE SCHEMA REQUIREMENTS
-- =====================================================
-- This file documents the required schema structure.
-- Run this BEFORE the RLS policies migration.
--
-- NOTE: Many of these tables likely already exist in your database.
-- This is provided as reference and for any missing pieces.

-- =====================================================
-- 1. FAMILIES TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS families (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_by TEXT NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_families_created_by ON families(created_by);

-- =====================================================
-- 2. FAMILY_MEMBERS TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS family_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(family_id, user_id)
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_family_members_family_id ON family_members(family_id);
CREATE INDEX IF NOT EXISTS idx_family_members_user_id ON family_members(user_id);

-- =====================================================
-- 3. FAMILY_INVITES TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS family_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  invited_email TEXT,  -- Optional, can be NULL for open invites
  token TEXT NOT NULL UNIQUE,
  share_code TEXT UNIQUE,  -- Short human-readable code
  expires_at TIMESTAMPTZ NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'revoked', 'expired')),
  accepted_by TEXT REFERENCES auth.users(id) ON DELETE SET NULL,
  accepted_at TIMESTAMPTZ,
  created_by TEXT NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_family_invites_family_id ON family_invites(family_id);
CREATE INDEX IF NOT EXISTS idx_family_invites_token ON family_invites(token);
CREATE INDEX IF NOT EXISTS idx_family_invites_share_code ON family_invites(share_code);
CREATE INDEX IF NOT EXISTS idx_family_invites_status ON family_invites(status);

-- =====================================================
-- 4. DOGS TABLE (Add family_id if not exists)
-- =====================================================
-- Add family_id column to existing dogs table
ALTER TABLE dogs 
  ADD COLUMN IF NOT EXISTS family_id TEXT REFERENCES families(id) ON DELETE CASCADE;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_dogs_family_id ON dogs(family_id);

-- If you want to backfill existing dogs into families:
-- You'll need to create a family for each existing user and assign their dogs
-- Example:
-- INSERT INTO families (id, name, created_by)
-- SELECT gen_random_uuid(), 'My Family', user_id
-- FROM dogs
-- GROUP BY user_id;
--
-- UPDATE dogs d
-- SET family_id = f.id
-- FROM families f
-- WHERE d.user_id = f.created_by;

-- =====================================================
-- 5. ENSURE ALL DOG-RELATED TABLES EXIST
-- =====================================================
-- These should already exist, but here for reference:

-- Activity logs must have dog_id
-- ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS dog_id TEXT REFERENCES dogs(id) ON DELETE CASCADE;
-- CREATE INDEX IF NOT EXISTS idx_activity_logs_dog_id ON activity_logs(dog_id);

-- Reminders must have dog_id
-- ALTER TABLE reminders ADD COLUMN IF NOT EXISTS dog_id TEXT REFERENCES dogs(id) ON DELETE CASCADE;
-- CREATE INDEX IF NOT EXISTS idx_reminders_dog_id ON reminders(dog_id);

-- Reminder occurrences must have dog_id
-- ALTER TABLE reminder_occurrences ADD COLUMN IF NOT EXISTS dog_id TEXT REFERENCES dogs(id) ON DELETE CASCADE;
-- CREATE INDEX IF NOT EXISTS idx_reminder_occurrences_dog_id ON reminder_occurrences(dog_id);

-- Goals preferences must have dog_id
-- ALTER TABLE goals_preferences ADD COLUMN IF NOT EXISTS dog_id TEXT REFERENCES dogs(id) ON DELETE CASCADE;
-- CREATE INDEX IF NOT EXISTS idx_goals_preferences_dog_id ON goals_preferences(dog_id);

-- Dog goals must have dog_id
-- ALTER TABLE dog_goals ADD COLUMN IF NOT EXISTS dog_id TEXT REFERENCES dogs(id) ON DELETE CASCADE;
-- CREATE INDEX IF NOT EXISTS idx_dog_goals_dog_id ON dog_goals(dog_id);

-- =====================================================
-- 6. USER PROFILE ENRICHMENT (Optional)
-- =====================================================
-- You may want to create a public.users table to store display names
-- This helps with showing who's in the family

CREATE TABLE IF NOT EXISTS public.users (
  id TEXT PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on public.users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Users can view other users in their families
CREATE POLICY "Users can view family members' profiles"
  ON public.users FOR SELECT
  USING (
    id IN (
      SELECT fm.user_id
      FROM family_members fm
      WHERE fm.family_id IN (
        SELECT family_id
        FROM family_members
        WHERE user_id = auth.uid()::text
      )
    )
  );

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON public.users FOR UPDATE
  USING (id = auth.uid()::text)
  WITH CHECK (id = auth.uid()::text);

-- Users can insert their own profile
CREATE POLICY "Users can insert own profile"
  ON public.users FOR INSERT
  WITH CHECK (id = auth.uid()::text);

-- Trigger to create user profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, display_name)
  VALUES (
    NEW.id::text,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'display_name', SPLIT_PART(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();

-- =====================================================
-- DONE! Schema is ready for RLS policies
-- =====================================================

