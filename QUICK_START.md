# Quick Start: Enable Multi-User in 5 Minutes

This is the fastest way to enable multi-user collaboration in your Dobbie Dog App.

## Prerequisites
- Supabase project already set up
- App already using Supabase Auth

## Steps

### 1. Run SQL Migrations (3 minutes)

Open **Supabase Dashboard → SQL Editor**

**Copy and run these two files in order:**

1. First: `supabase_migrations/00_schema_requirements.sql`
2. Then: `supabase_migrations/01_rls_policies.sql`

✅ **Done!** Your database is now secured and ready for teams.

### 2. Enable Realtime (1 minute)

Go to **Database → Replication**

Toggle ON for these tables:
- `activity_logs`
- `dogs`
- `reminders`
- `reminder_occurrences`
- `family_members`

### 3. Test It (1 minute)

**On Device 1:**
1. Open app → Settings
2. Tap "Generate share code"
3. Copy the 6-character code (e.g., "A1B2C3")

**On Device 2:**
1. Create new account
2. During setup: Toggle "Join an existing family"
3. Enter the share code
4. Tap "Join"

**Verify:**
- Device 2 should see Device 1's dog
- Log an activity on Device 1 → appears instantly on Device 2
- Log an activity on Device 2 → appears instantly on Device 1

## That's It! 🎉

Your app now supports:
- ✅ Real-time collaboration
- ✅ Secure data isolation
- ✅ Team member management
- ✅ Invite system

## Common Issues

**"Permission denied"**
→ Make sure both SQL files ran successfully

**"No dog found"**
→ Join a family first, or create a dog to auto-create a family

**Realtime not working**
→ Check that Realtime is enabled on all tables

## What Just Happened?

1. **RLS Policies** protect your data so users only see their family's data
2. **Helper Functions** check family membership for all queries
3. **Triggers** automatically add users to families they create
4. **Realtime** syncs changes instantly across all devices
5. **UI Updates** added member management to Settings tab

## Next Steps

- Read the full guide: `MULTI_USER_SETUP.md`
- Customize invite expiration times
- Add role-based permissions
- Enable push notifications for team activities

## Need Help?

Check the troubleshooting section in `MULTI_USER_SETUP.md`

