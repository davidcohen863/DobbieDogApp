# Multi-User Setup Guide for Dobbie Dog App

This guide will walk you through setting up multi-user collaboration features for your Dobbie Dog App using Supabase.

## Overview

Your app now supports:
- ✅ **Family-based collaboration** - Multiple users can manage the same dog(s)
- ✅ **Row-Level Security (RLS)** - Users only see data they have access to
- ✅ **Real-time sync** - Changes appear instantly for all team members
- ✅ **Invite system** - Two ways to invite: shareable links or short codes
- ✅ **Member management** - View, add, and remove family members

## Architecture

### Database Schema

```
families
├── dogs (family_id)
│   ├── activity_logs (dog_id)
│   ├── reminders (dog_id)
│   ├── reminder_occurrences (dog_id)
│   ├── goals_preferences (dog_id)
│   └── dog_goals (dog_id)
└── family_members (family_id, user_id)
    └── family_invites (family_id)
```

**Key relationships:**
- Each `family` has multiple `family_members`
- Each `family` has multiple `dogs`
- Each `dog` has multiple `activity_logs`, `reminders`, etc.
- Users access dogs through their family membership

## Step-by-Step Setup

### Step 1: Apply Database Migrations

**Important:** Run these SQL files in your Supabase SQL Editor in order:

1. **Schema Requirements** (if needed):
   ```sql
   -- File: supabase_migrations/00_schema_requirements.sql
   -- This adds missing columns and tables
   ```
   
   Open your Supabase Dashboard → SQL Editor → New Query
   - Copy the contents of `00_schema_requirements.sql`
   - Paste and run
   - Check for any errors (most tables likely already exist)

2. **RLS Policies** (critical for security):
   ```sql
   -- File: supabase_migrations/01_rls_policies.sql
   -- This secures all tables with proper access control
   ```
   
   Open Supabase Dashboard → SQL Editor → New Query
   - Copy the contents of `01_rls_policies.sql`
   - Paste and run
   - This will enable RLS and create all security policies

### Step 2: Enable Realtime in Supabase

For real-time collaboration, you need to enable Realtime on certain tables:

1. Go to: Supabase Dashboard → Database → Replication
2. Enable Realtime for these tables:
   - ✅ `activity_logs`
   - ✅ `dogs`
   - ✅ `reminders`
   - ✅ `reminder_occurrences`
   - ✅ `family_members`
   - ✅ `families`

**How to enable:**
- Click the table name
- Toggle "Enable Realtime" to ON
- Click "Save"

### Step 3: Migrate Existing Data (Optional)

If you have existing users with dogs, you need to migrate them into families:

```sql
-- Create a family for each existing user
INSERT INTO families (id, name, created_by)
SELECT 
  gen_random_uuid()::text,
  'My Family',
  user_id
FROM dogs
GROUP BY user_id
ON CONFLICT DO NOTHING;

-- Add creators as family members
INSERT INTO family_members (family_id, user_id)
SELECT 
  f.id,
  f.created_by
FROM families f
ON CONFLICT DO NOTHING;

-- Link existing dogs to their user's family
UPDATE dogs d
SET family_id = f.id
FROM families f
WHERE d.user_id = f.created_by
  AND d.family_id IS NULL;
```

### Step 4: Verify RLS is Working

Test that RLS policies are working correctly:

```sql
-- Test as a user (replace with actual user ID)
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims TO '{"sub": "your-user-id-here"}';

-- Should only return families you're a member of
SELECT * FROM families;

-- Should only return dogs in your families
SELECT * FROM dogs;

-- Reset
RESET ROLE;
```

## How Users Collaborate

### Creating a Family

When a user creates their first dog, a family is automatically created for them via the database trigger.

Alternatively, users can explicitly create families in Settings:
1. Open app → Settings tab
2. If no family exists, tap "Create new family"
3. The user becomes the family creator and first member

### Inviting Team Members

There are two ways to invite someone:

#### Option 1: Share Code (Recommended)
1. Settings → Generate share code
2. Share the 6-character code (e.g., "A1B2C3")
3. New user enters code during setup or in Settings
4. Code expires in 7 days

#### Option 2: Invite Link
1. Settings → Invite via link
2. Share the URL (e.g., https://dobbie.app/join?token=...)
3. New user clicks link to join
4. Link expires in 7 days

### Joining a Family

**During Setup:**
- New users see "Join an existing family" toggle
- Enter share code
- Automatically get access to the family's dogs

**After Setup:**
- Settings → Enter share code
- Join additional families

### Managing Members

**View members:**
- Settings → Family Members section
- Shows all members with their email

**Remove members (Creator only):**
- Tap the ❌ button next to a member's name
- Confirm removal

**Leave family:**
- Non-creators can leave via "Leave Family" button
- Creators cannot leave their own family

## Real-time Sync

The app uses Supabase Realtime to sync changes instantly across all devices.

### What Syncs in Real-time:

1. **Activity Logs** - Walks, meals, potty breaks, sleep
2. **Dogs** - Profile updates, new dogs added
3. **Reminders** - New reminders, edits, completions
4. **Family Members** - When someone joins or leaves

### Testing Real-time Sync:

1. Open app on Device A (User 1)
2. Open app on Device B (User 2) - same family
3. On Device A: Log a walk
4. On Device B: Should appear instantly without refresh
5. On Device B: Complete a reminder
6. On Device A: Should update instantly

## Security Features

### Row-Level Security (RLS)

Every table is protected by RLS policies that ensure:
- Users only see data for families they're members of
- Users can only modify data they have access to
- Family creators can manage members
- All operations respect family boundaries

### What Each User Can Do:

| Action | Family Member | Family Creator |
|--------|--------------|----------------|
| View dogs & activities | ✅ | ✅ |
| Add/edit activities | ✅ | ✅ |
| Create reminders | ✅ | ✅ |
| Create invites | ✅ | ✅ |
| View family members | ✅ | ✅ |
| Remove members | ❌ | ✅ |
| Leave family | ✅ | ❌ |
| Delete family | ❌ | ✅ |

## Troubleshooting

### Issue: "No dog profile found"

**Cause:** User isn't a member of any family, or family has no dogs.

**Solution:**
1. User should join a family via share code, OR
2. Create their first dog (automatically creates a family)

### Issue: "Can't see other user's activities"

**Possible causes:**
1. Users are in different families
2. RLS policies not applied
3. Realtime not enabled

**Solution:**
1. Verify both users are in same family: `SELECT * FROM family_members WHERE family_id = 'family-id';`
2. Check RLS is enabled: `SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public';`
3. Enable Realtime on `activity_logs` table

### Issue: "Permission denied" errors

**Cause:** RLS policies blocking access (as intended) or misconfigured.

**Solution:**
1. Check user is in the family: `SELECT * FROM family_members WHERE user_id = auth.uid()::text;`
2. Verify RLS policies are active
3. Check Supabase logs for detailed error

### Issue: Realtime not working

**Checklist:**
- [ ] Realtime enabled on table in Supabase Dashboard
- [ ] User has RLS SELECT permission on table
- [ ] Network connection stable
- [ ] Channel subscribed successfully (check console logs)

**Solution:**
```swift
// In your view, ensure realtime is started
.task {
    if let dogId = try? await SupabaseManager.shared.getDogId(),
       let familyId = SupabaseManager.shared.getActiveFamilyId() {
        await SupabaseManager.shared.startAllRealtime(
            dogId: dogId,
            familyId: familyId,
            onActivityChange: { /* refresh */ },
            onDogsChange: { /* refresh */ },
            onRemindersChange: { /* refresh */ },
            onMembersChange: { /* refresh */ }
        )
    }
}
```

## Testing Checklist

Use this checklist to verify everything works:

### Basic Setup
- [ ] Run both SQL migration files successfully
- [ ] Enable Realtime on all required tables
- [ ] Migrate existing data if needed

### User Flow
- [ ] Create account → auto-creates family
- [ ] Create first dog → linked to family
- [ ] Log activity → appears in activity list
- [ ] Create reminder → appears in calendar

### Collaboration
- [ ] Generate share code
- [ ] Second user joins via code
- [ ] Both users see same dog
- [ ] User A logs walk → User B sees it instantly
- [ ] User B creates reminder → User A sees it instantly
- [ ] View family members list
- [ ] Creator removes member
- [ ] Member leaves family

### Security
- [ ] User cannot see other families' dogs
- [ ] Removed user loses access immediately
- [ ] Non-creator cannot remove members
- [ ] Creator cannot leave their family

## Advanced: Customization

### Changing Invite Expiration

Default: 7 days. To change:

```swift
// In SettingsView.swift, line ~239
let res = try await SupabaseManager.shared.createFamilyShareCode(
    familyId: fid,
    minutes: 60 * 24 * 14  // 14 days instead of 7
)
```

### Adding Role-Based Permissions

To add roles (owner, admin, member):

1. Add `role` column to `family_members`:
```sql
ALTER TABLE family_members 
ADD COLUMN role TEXT DEFAULT 'member' 
CHECK (role IN ('owner', 'admin', 'member'));
```

2. Update RLS policies to check role
3. Update UI to show role badges

### Enabling Public Profile Display

To show user names instead of emails:

1. Run the `public.users` table creation from `00_schema_requirements.sql`
2. Update `FamilyMemberWithUser` to join with `public.users`
3. Let users set their display name in Settings

## Support

If you encounter issues:
1. Check Supabase logs: Dashboard → Logs → API/Realtime
2. Check app logs for detailed error messages
3. Verify RLS policies: Dashboard → Authentication → Policies
4. Test SQL queries directly in SQL Editor

## Next Steps

Consider adding:
- [ ] Push notifications when family members add activities
- [ ] Activity feed showing "Who did what"
- [ ] Multiple dogs per family with different access levels
- [ ] Family settings (name, avatar, preferences)
- [ ] Activity comments/reactions
- [ ] Shared photo albums per dog

---

**Note:** Always test changes in a development environment before applying to production!

