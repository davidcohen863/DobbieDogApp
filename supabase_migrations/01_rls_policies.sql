-- =====================================================
-- Row-Level Security (RLS) Setup for Multi-User Support
-- =====================================================
-- Run this in your Supabase SQL Editor to enable team collaboration
-- with proper security isolation.

-- =====================================================
-- 1. HELPER FUNCTIONS
-- =====================================================

-- Check if user is a member of a family
CREATE OR REPLACE FUNCTION is_family_member(family_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM family_members
    WHERE family_id = family_uuid::text
      AND user_id = auth.uid()::text
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get all family IDs that the current user is a member of
CREATE OR REPLACE FUNCTION user_family_ids()
RETURNS SETOF TEXT AS $$
BEGIN
  RETURN QUERY
  SELECT family_id
  FROM family_members
  WHERE user_id = auth.uid()::text;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if user has access to a specific dog (via family membership)
CREATE OR REPLACE FUNCTION has_dog_access(dog_uuid TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM dogs d
    INNER JOIN family_members fm ON d.family_id = fm.family_id
    WHERE d.id = dog_uuid
      AND fm.user_id = auth.uid()::text
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 2. ENABLE RLS ON ALL TABLES
-- =====================================================

ALTER TABLE families ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE dogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminder_occurrences ENABLE ROW LEVEL SECURITY;
ALTER TABLE goals_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE dog_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- 3. FAMILIES TABLE POLICIES
-- =====================================================

-- Users can view families they are members of
CREATE POLICY "Users can view their families"
  ON families FOR SELECT
  USING (
    id IN (SELECT user_family_ids())
  );

-- Users can create families (they become owner/member via trigger)
CREATE POLICY "Users can create families"
  ON families FOR INSERT
  WITH CHECK (
    created_by = auth.uid()::text
  );

-- Only family creator can update family details
CREATE POLICY "Family creators can update their families"
  ON families FOR UPDATE
  USING (
    created_by = auth.uid()::text
  )
  WITH CHECK (
    created_by = auth.uid()::text
  );

-- Only family creator can delete (optional - you may want to prevent this)
CREATE POLICY "Family creators can delete their families"
  ON families FOR DELETE
  USING (
    created_by = auth.uid()::text
  );

-- =====================================================
-- 4. FAMILY_MEMBERS TABLE POLICIES
-- =====================================================

-- Users can view members of families they belong to
CREATE POLICY "Users can view their family members"
  ON family_members FOR SELECT
  USING (
    family_id IN (SELECT user_family_ids())
  );

-- System inserts members (via invite acceptance or triggers)
CREATE POLICY "System can insert family members"
  ON family_members FOR INSERT
  WITH CHECK (
    -- Either the user is joining themselves via invite
    user_id = auth.uid()::text
    OR
    -- Or the family creator is adding them
    EXISTS (
      SELECT 1 FROM families
      WHERE id = family_id
        AND created_by = auth.uid()::text
    )
  );

-- Only family creator can remove members
CREATE POLICY "Family creators can remove members"
  ON family_members FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM families
      WHERE id = family_id
        AND created_by = auth.uid()::text
    )
  );

-- =====================================================
-- 5. FAMILY_INVITES TABLE POLICIES
-- =====================================================

-- Users can view invites for their families
CREATE POLICY "Users can view invites for their families"
  ON family_invites FOR SELECT
  USING (
    family_id IN (SELECT user_family_ids())
  );

-- Users can create invites for their families
CREATE POLICY "Family members can create invites"
  ON family_invites FOR INSERT
  WITH CHECK (
    family_id IN (SELECT user_family_ids())
    AND created_by = auth.uid()::text
  );

-- Users can update invites for their families (revoke, etc.)
CREATE POLICY "Family members can update invites"
  ON family_invites FOR UPDATE
  USING (
    family_id IN (SELECT user_family_ids())
  )
  WITH CHECK (
    family_id IN (SELECT user_family_ids())
  );

-- =====================================================
-- 6. DOGS TABLE POLICIES
-- =====================================================

-- Users can view dogs in their families
CREATE POLICY "Users can view family dogs"
  ON dogs FOR SELECT
  USING (
    family_id IN (SELECT user_family_ids())
  );

-- Users can create dogs in their families
CREATE POLICY "Family members can create dogs"
  ON dogs FOR INSERT
  WITH CHECK (
    family_id IN (SELECT user_family_ids())
  );

-- Users can update dogs in their families
CREATE POLICY "Family members can update dogs"
  ON dogs FOR UPDATE
  USING (
    family_id IN (SELECT user_family_ids())
  )
  WITH CHECK (
    family_id IN (SELECT user_family_ids())
  );

-- Users can delete dogs in their families
CREATE POLICY "Family members can delete dogs"
  ON dogs FOR DELETE
  USING (
    family_id IN (SELECT user_family_ids())
  );

-- =====================================================
-- 7. ACTIVITY_LOGS TABLE POLICIES
-- =====================================================

-- Users can view activity logs for dogs they have access to
CREATE POLICY "Users can view activity logs for accessible dogs"
  ON activity_logs FOR SELECT
  USING (
    has_dog_access(dog_id)
  );

-- Users can create activity logs for accessible dogs
CREATE POLICY "Users can create activity logs for accessible dogs"
  ON activity_logs FOR INSERT
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- Users can update activity logs for accessible dogs
CREATE POLICY "Users can update activity logs for accessible dogs"
  ON activity_logs FOR UPDATE
  USING (
    has_dog_access(dog_id)
  )
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- Users can delete activity logs for accessible dogs
CREATE POLICY "Users can delete activity logs for accessible dogs"
  ON activity_logs FOR DELETE
  USING (
    has_dog_access(dog_id)
  );

-- =====================================================
-- 8. REMINDERS TABLE POLICIES
-- =====================================================

-- Users can view reminders for dogs they have access to
CREATE POLICY "Users can view reminders for accessible dogs"
  ON reminders FOR SELECT
  USING (
    has_dog_access(dog_id)
  );

-- Users can create reminders for accessible dogs
CREATE POLICY "Users can create reminders for accessible dogs"
  ON reminders FOR INSERT
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- Users can update reminders for accessible dogs
CREATE POLICY "Users can update reminders for accessible dogs"
  ON reminders FOR UPDATE
  USING (
    has_dog_access(dog_id)
  )
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- Users can delete reminders for accessible dogs
CREATE POLICY "Users can delete reminders for accessible dogs"
  ON reminders FOR DELETE
  USING (
    has_dog_access(dog_id)
  );

-- =====================================================
-- 9. REMINDER_OCCURRENCES TABLE POLICIES
-- =====================================================

-- Users can view reminder occurrences for accessible dogs
CREATE POLICY "Users can view reminder occurrences for accessible dogs"
  ON reminder_occurrences FOR SELECT
  USING (
    has_dog_access(dog_id)
  );

-- Users can create reminder occurrences for accessible dogs
CREATE POLICY "Users can create reminder occurrences for accessible dogs"
  ON reminder_occurrences FOR INSERT
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- Users can update reminder occurrences for accessible dogs
CREATE POLICY "Users can update reminder occurrences for accessible dogs"
  ON reminder_occurrences FOR UPDATE
  USING (
    has_dog_access(dog_id)
  )
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- Users can delete reminder occurrences for accessible dogs
CREATE POLICY "Users can delete reminder occurrences for accessible dogs"
  ON reminder_occurrences FOR DELETE
  USING (
    has_dog_access(dog_id)
  );

-- =====================================================
-- 10. GOALS_PREFERENCES TABLE POLICIES
-- =====================================================

-- Users can view goals for accessible dogs
CREATE POLICY "Users can view goals for accessible dogs"
  ON goals_preferences FOR SELECT
  USING (
    has_dog_access(dog_id)
  );

-- Users can create goals for accessible dogs
CREATE POLICY "Users can create goals for accessible dogs"
  ON goals_preferences FOR INSERT
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- Users can update goals for accessible dogs
CREATE POLICY "Users can update goals for accessible dogs"
  ON goals_preferences FOR UPDATE
  USING (
    has_dog_access(dog_id)
  )
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- Users can delete goals for accessible dogs
CREATE POLICY "Users can delete goals for accessible dogs"
  ON goals_preferences FOR DELETE
  USING (
    has_dog_access(dog_id)
  );

-- =====================================================
-- 11. DOG_GOALS TABLE POLICIES
-- =====================================================

-- Users can view dog goals for accessible dogs
CREATE POLICY "Users can view dog goals for accessible dogs"
  ON dog_goals FOR SELECT
  USING (
    has_dog_access(dog_id)
  );

-- Users can create dog goals for accessible dogs
CREATE POLICY "Users can create dog goals for accessible dogs"
  ON dog_goals FOR INSERT
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- Users can update dog goals for accessible dogs
CREATE POLICY "Users can update dog goals for accessible dogs"
  ON dog_goals FOR UPDATE
  USING (
    has_dog_access(dog_id)
  )
  WITH CHECK (
    has_dog_access(dog_id)
  );

-- =====================================================
-- 12. CHATS TABLE POLICIES
-- =====================================================

-- Users can view their own chat messages
CREATE POLICY "Users can view their own chats"
  ON chats FOR SELECT
  USING (
    user_id = auth.uid()::text
  );

-- Users can create their own chat messages
CREATE POLICY "Users can create their own chats"
  ON chats FOR INSERT
  WITH CHECK (
    user_id = auth.uid()::text
  );

-- Users can update their own chat messages
CREATE POLICY "Users can update their own chats"
  ON chats FOR UPDATE
  USING (
    user_id = auth.uid()::text
  )
  WITH CHECK (
    user_id = auth.uid()::text
  );

-- Users can delete their own chat messages
CREATE POLICY "Users can delete their own chats"
  ON chats FOR DELETE
  USING (
    user_id = auth.uid()::text
  );

-- =====================================================
-- 13. DEVICE_TOKENS TABLE POLICIES
-- =====================================================

-- Users can view their own device tokens
CREATE POLICY "Users can view their own device tokens"
  ON device_tokens FOR SELECT
  USING (
    user_id = auth.uid()::text
  );

-- Users can create their own device tokens
CREATE POLICY "Users can create their own device tokens"
  ON device_tokens FOR INSERT
  WITH CHECK (
    user_id = auth.uid()::text
  );

-- Users can update their own device tokens
CREATE POLICY "Users can update their own device tokens"
  ON device_tokens FOR UPDATE
  USING (
    user_id = auth.uid()::text
  )
  WITH CHECK (
    user_id = auth.uid()::text
  );

-- Users can delete their own device tokens
CREATE POLICY "Users can delete their own device tokens"
  ON device_tokens FOR DELETE
  USING (
    user_id = auth.uid()::text
  );

-- =====================================================
-- 14. TRIGGERS FOR AUTO-MEMBERSHIP
-- =====================================================

-- Automatically add family creator as a member when family is created
CREATE OR REPLACE FUNCTION auto_add_family_creator()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO family_members (family_id, user_id)
  VALUES (NEW.id, NEW.created_by)
  ON CONFLICT (family_id, user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS on_family_created ON families;
CREATE TRIGGER on_family_created
  AFTER INSERT ON families
  FOR EACH ROW
  EXECUTE FUNCTION auto_add_family_creator();

-- =====================================================
-- 15. AUTO-ASSIGN FAMILY TO NEW DOGS
-- =====================================================

-- Automatically assign dog to user's active family if not specified
-- (Optional - you may want to always require explicit family_id)
CREATE OR REPLACE FUNCTION auto_assign_dog_family()
RETURNS TRIGGER AS $$
BEGIN
  -- If family_id is not set, assign to user's first family
  IF NEW.family_id IS NULL THEN
    SELECT family_id INTO NEW.family_id
    FROM family_members
    WHERE user_id = auth.uid()::text
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS on_dog_created ON dogs;
CREATE TRIGGER on_dog_created
  BEFORE INSERT ON dogs
  FOR EACH ROW
  EXECUTE FUNCTION auto_assign_dog_family();

-- =====================================================
-- 16. ACCEPT INVITE FUNCTIONS (if not already exist)
-- =====================================================

-- Accept invite by token (for URL-based invites)
CREATE OR REPLACE FUNCTION accept_family_invite(p_token TEXT)
RETURNS TABLE(accept_family_invite TEXT) AS $$
DECLARE
  v_invite_id TEXT;
  v_family_id TEXT;
  v_user_id TEXT := auth.uid()::text;
BEGIN
  -- Find valid invite
  SELECT id, family_id INTO v_invite_id, v_family_id
  FROM family_invites
  WHERE token = p_token
    AND status = 'pending'
    AND expires_at > NOW()
  LIMIT 1;

  IF v_invite_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired invite';
  END IF;

  -- Add user to family
  INSERT INTO family_members (family_id, user_id)
  VALUES (v_family_id, v_user_id)
  ON CONFLICT (family_id, user_id) DO NOTHING;

  -- Mark invite as accepted
  UPDATE family_invites
  SET status = 'accepted',
      accepted_by = v_user_id,
      accepted_at = NOW()
  WHERE id = v_invite_id;

  RETURN QUERY SELECT v_family_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Accept invite by share code
CREATE OR REPLACE FUNCTION accept_family_invite_by_code(p_share_code TEXT)
RETURNS TEXT AS $$
DECLARE
  v_invite_id TEXT;
  v_family_id TEXT;
  v_user_id TEXT := auth.uid()::text;
BEGIN
  -- Find valid invite by share code
  SELECT id, family_id INTO v_invite_id, v_family_id
  FROM family_invites
  WHERE share_code = UPPER(p_share_code)
    AND status = 'pending'
    AND expires_at > NOW()
  LIMIT 1;

  IF v_invite_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired share code';
  END IF;

  -- Add user to family
  INSERT INTO family_members (family_id, user_id)
  VALUES (v_family_id, v_user_id)
  ON CONFLICT (family_id, user_id) DO NOTHING;

  -- Mark invite as accepted
  UPDATE family_invites
  SET status = 'accepted',
      accepted_by = v_user_id,
      accepted_at = NOW()
  WHERE id = v_invite_id;

  RETURN v_family_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 17. CREATE SHARE CODE FUNCTION
-- =====================================================

CREATE OR REPLACE FUNCTION create_family_share_code(
  p_family_id TEXT,
  p_minutes INT DEFAULT 10080  -- 7 days default
)
RETURNS TABLE(share_code TEXT, expires_at TIMESTAMPTZ) AS $$
DECLARE
  v_code TEXT;
  v_expires TIMESTAMPTZ;
  v_user_id TEXT := auth.uid()::text;
BEGIN
  -- Check if user is a member of the family
  IF NOT is_family_member(p_family_id::UUID) THEN
    RAISE EXCEPTION 'Not authorized to create invite for this family';
  END IF;

  -- Generate 6-character hex code
  v_code := UPPER(SUBSTRING(encode(gen_random_bytes(3), 'hex') FROM 1 FOR 6));
  v_expires := NOW() + (p_minutes || ' minutes')::INTERVAL;

  -- Insert invite with share code
  INSERT INTO family_invites (
    family_id,
    share_code,
    token,  -- Generate a token too for consistency
    expires_at,
    created_by,
    status
  ) VALUES (
    p_family_id,
    v_code,
    encode(gen_random_bytes(24), 'hex'),
    v_expires,
    v_user_id,
    'pending'
  );

  RETURN QUERY SELECT v_code, v_expires;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- DONE! Your database is now secured with RLS
-- =====================================================
-- 
-- Next steps:
-- 1. Test by creating a family with one user
-- 2. Generate an invite and accept it with another user
-- 3. Verify both users can see the same dog and activities
-- 4. Verify users cannot access other families' data

