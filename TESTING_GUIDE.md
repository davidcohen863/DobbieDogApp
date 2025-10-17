# Multi-User Testing Guide

This guide helps you test all multi-user collaboration features systematically.

## Test Setup

### Requirements
- 2 iOS devices (or 1 device + 1 simulator)
- 2 different Supabase accounts
- Supabase project with migrations applied
- Realtime enabled on all tables

### Test Users
- **User A** (Alice): Family creator, primary tester
- **User B** (Bob): Family member, secondary tester

## Test Suite

### 1. Database Setup Tests

#### Test 1.1: Verify RLS is Enabled
```sql
-- Run in Supabase SQL Editor
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename IN (
    'families', 'family_members', 'family_invites', 
    'dogs', 'activity_logs', 'reminders'
  );
```

**Expected Result:** All tables show `rowsecurity = true`

#### Test 1.2: Verify Helper Functions Exist
```sql
SELECT proname 
FROM pg_proc 
WHERE proname IN (
  'is_family_member',
  'user_family_ids',
  'has_dog_access',
  'accept_family_invite',
  'accept_family_invite_by_code',
  'create_family_share_code'
);
```

**Expected Result:** All 6 functions exist

#### Test 1.3: Verify Triggers Are Active
```sql
SELECT tgname, tgrelid::regclass, tgenabled
FROM pg_trigger
WHERE tgname IN ('on_family_created', 'on_dog_created');
```

**Expected Result:** Both triggers show `tgenabled = O` (enabled)

### 2. User Onboarding Tests

#### Test 2.1: New User Creates Family
**Steps (User A):**
1. Create account
2. Complete setup, create first dog
3. Open Settings tab

**Expected Results:**
- ✅ Family automatically created
- ✅ Settings shows "My Family" 
- ✅ User A appears in "Family Members" section
- ✅ Badge shows "You"

**Verify in Database:**
```sql
SELECT f.name, fm.user_id, u.email
FROM families f
JOIN family_members fm ON f.id = fm.family_id
JOIN auth.users u ON fm.user_id = u.id::text
WHERE u.email = 'alice@example.com';
```

#### Test 2.2: New User Joins Existing Family
**Steps (User A):**
1. Settings → Generate share code
2. Note the code (e.g., "ABC123")

**Steps (User B):**
1. Create account
2. During setup: Toggle "Join an existing family"
3. Enter share code "ABC123"
4. Tap "Join"

**Expected Results:**
- ✅ "Setup Complete" appears
- ✅ User B sees User A's dog
- ✅ User B can access Home/Calendar/Chat tabs

**Verify in Database:**
```sql
SELECT fm.user_id, u.email, fm.joined_at
FROM family_members fm
JOIN auth.users u ON fm.user_id = u.id::text
WHERE fm.family_id = (
  SELECT family_id FROM family_members 
  WHERE user_id = (SELECT id::text FROM auth.users WHERE email = 'alice@example.com')
  LIMIT 1
);
```

Should show both alice@example.com and bob@example.com

### 3. Activity Logging Tests

#### Test 3.1: Basic Activity Logging
**Steps (User A):**
1. Home tab → Tap "Walk"
2. Wait 2 seconds

**Expected Results (User B):**
- ✅ Walk appears in Home feed instantly
- ✅ Walk appears in Calendar view
- ✅ No manual refresh needed

**Steps (User B):**
1. Home tab → Tap "Meal"
2. Wait 2 seconds

**Expected Results (User A):**
- ✅ Meal appears in Home feed instantly
- ✅ Meal appears in Calendar view

#### Test 3.2: Activity Editing
**Steps (User A):**
1. Calendar → Tap on User B's meal
2. Edit → Add note "Large portion"
3. Save

**Expected Results (User B):**
- ✅ Note appears in meal details within 2 seconds
- ✅ No error or overwrite conflict

#### Test 3.3: Activity Deletion
**Steps (User B):**
1. Calendar → Tap on a walk
2. Delete → Confirm

**Expected Results (User A):**
- ✅ Walk disappears from calendar within 2 seconds
- ✅ Walk disappears from Home feed

### 4. Reminder Tests

#### Test 4.1: Create Reminder
**Steps (User A):**
1. Calendar → "+" → Add Reminder
2. Title: "Evening walk"
3. Schedule: Daily at 18:00
4. Save

**Expected Results (User B):**
- ✅ Reminder appears in Calendar within 2 seconds
- ✅ Shows same time (18:00)
- ✅ Reminder is enabled

#### Test 4.2: Complete Reminder
**Steps (User B):**
1. When reminder fires (or manually in Calendar)
2. Mark as complete

**Expected Results (User A):**
- ✅ Reminder shows as completed within 2 seconds
- ✅ Green checkmark appears
- ✅ Next occurrence still scheduled

#### Test 4.3: Edit Reminder
**Steps (User A):**
1. Calendar → Tap reminder → Edit
2. Change time to 19:00
3. Save

**Expected Results (User B):**
- ✅ Reminder time updates to 19:00 within 2 seconds
- ✅ Future occurrences reflect new time

### 5. Family Management Tests

#### Test 5.1: View Members
**Steps (User A):**
1. Settings → Family Members section

**Expected Results:**
- ✅ Shows User A (with "You" badge)
- ✅ Shows User B (with email)
- ✅ Shows joined date for User B

**Steps (User B):**
1. Settings → Family Members section

**Expected Results:**
- ✅ Shows User A (creator)
- ✅ Shows User B (with "You" badge)
- ✅ No "remove" buttons (not creator)
- ✅ "Leave Family" button visible

#### Test 5.2: Remove Member (Creator Only)
**Steps (User A):**
1. Settings → Family Members
2. Tap ❌ next to User B
3. Confirm removal

**Expected Results (User B):**
- ✅ Immediately loses access to dog data
- ✅ "No dog profile found" error OR
- ✅ Redirected to Setup screen
- ✅ Settings shows no families

**Expected Results (User A):**
- ✅ User B removed from member list
- ✅ Haptic feedback confirms action

**Verify in Database:**
```sql
SELECT COUNT(*) as member_count
FROM family_members
WHERE family_id = 'family-id-here';
```
Should return 1 (only User A)

#### Test 5.3: Leave Family
**Prerequisite:** Re-invite User B

**Steps (User B):**
1. Settings → "Leave Family"
2. Confirm

**Expected Results (User B):**
- ✅ Switches to another family (if member of multiple) OR
- ✅ Settings shows "No families yet"
- ✅ Loses access to User A's dog

**Expected Results (User A):**
- ✅ User B disappears from member list within 2 seconds

### 6. Invite System Tests

#### Test 6.1: Share Code Generation
**Steps (User A):**
1. Settings → "Generate share code"

**Expected Results:**
- ✅ Modal shows 6-character code (e.g., "A1B2C3")
- ✅ Shows expiration date (7 days from now)
- ✅ "Copy" and "Share" buttons work
- ✅ Code appears in "Pending Invites" list

#### Test 6.2: Share Code Expiration
**Steps:**
1. In database, set invite expires_at to past:
```sql
UPDATE family_invites 
SET expires_at = NOW() - INTERVAL '1 day'
WHERE share_code = 'ABC123';
```

2. Try to join with that code

**Expected Results:**
- ✅ Error: "Invalid or expired share code"
- ✅ User not added to family

#### Test 6.3: Invalid Share Code
**Steps (User C - new user):**
1. Setup → Join family
2. Enter code: "XXXXXX"
3. Tap "Join"

**Expected Results:**
- ✅ Error: "Invalid or expired share code"
- ✅ Stays on setup screen
- ✅ Can try again

#### Test 6.4: Revoke Invite
**Steps (User A):**
1. Settings → Pending Invites
2. Tap menu on an invite
3. Tap "Revoke"

**Expected Results:**
- ✅ Invite disappears from list
- ✅ Code no longer works for joining

**Verify in Database:**
```sql
SELECT status FROM family_invites WHERE id = 'invite-id';
```
Should return `status = 'revoked'`

### 7. Real-time Sync Tests

#### Test 7.1: Connection Test
**Steps (both users):**
1. Enable Airplane Mode
2. Try to log activity

**Expected Results:**
- ✅ Activity saved locally (if offline support enabled) OR
- ✅ Error message shown
- ✅ Disable Airplane Mode → activity syncs

#### Test 7.2: Rapid Sequential Changes
**Steps:**
1. User A: Log walk
2. User B: Immediately log meal
3. User A: Immediately log potty
4. User B: Immediately log play

**Expected Results:**
- ✅ All 4 activities appear in correct order
- ✅ No activities lost
- ✅ Both users see all 4 activities

#### Test 7.3: Concurrent Editing
**Steps:**
1. User A: Start editing walk notes
2. User B: Start editing same walk at same time
3. User A: Save "Long walk"
4. User B: Save "With treats"

**Expected Results:**
- ✅ Last save wins (User B's "With treats") OR
- ✅ Conflict resolution UI appears
- ✅ No data corruption

### 8. Security Tests

#### Test 8.1: Unauthorized Access
**Steps:**
1. User C (not in family) logs in
2. Try to access User A's dog via direct API call:
```swift
let dogs: [Dog] = try await SupabaseManager.shared.client
    .from("dogs")
    .select()
    .eq("id", value: "user-a-dog-id")
    .execute()
    .value
```

**Expected Results:**
- ✅ Empty array returned (RLS blocks access)
- ✅ No error thrown
- ✅ User C cannot see User A's data

#### Test 8.2: Removed Member Access
**Prerequisite:** User B was removed from family

**Steps (User B):**
1. Try to view activities
2. Try to create activity
3. Try to edit reminder

**Expected Results:**
- ✅ All operations fail with "No dog profile found" OR
- ✅ Operations blocked by RLS
- ✅ No data leaked

#### Test 8.3: Non-Creator Permissions
**Steps (User B):**
1. Try to remove User A from family
2. Try to delete family

**Expected Results:**
- ✅ Remove button not visible
- ✅ API call fails if attempted directly
- ✅ User A remains in family

### 9. Edge Case Tests

#### Test 9.1: Last Member Leaves
**Steps:**
1. Create family with 2 members
2. Creator removes second member
3. Creator leaves family (should fail)

**Expected Results:**
- ✅ Creator cannot leave their own family
- ✅ "Leave Family" button not visible for creator

#### Test 9.2: Multiple Families
**Steps (User A):**
1. Create Family 1, add dog "Max"
2. Join Family 2 (via invite)
3. Settings → Switch between families

**Expected Results:**
- ✅ Picker shows both families
- ✅ Switching families changes visible dogs
- ✅ Data isolation maintained
- ✅ Activities saved to correct dog

#### Test 9.3: Deleted Dog
**Steps:**
1. User A deletes dog
2. User B tries to log activity for that dog

**Expected Results:**
- ✅ User B sees "No dog profile found"
- ✅ Cannot log activities
- ✅ Both users need to select/create another dog

### 10. Performance Tests

#### Test 10.1: Large Family
**Setup:** Create family with 10 members

**Steps:**
1. All 10 users log activities simultaneously
2. Measure time for realtime sync

**Expected Results:**
- ✅ All activities appear within 3 seconds
- ✅ No duplicate activities
- ✅ UI remains responsive

#### Test 10.2: Many Activities
**Setup:** Family with 1000+ activity logs

**Steps:**
1. Load calendar view
2. Scroll through months
3. Filter by type

**Expected Results:**
- ✅ Calendar loads in < 2 seconds
- ✅ Scrolling is smooth
- ✅ Filtering is instant
- ✅ No memory issues

## Test Results Template

Use this template to track your testing:

```
| Test ID | Test Name | Pass/Fail | Notes |
|---------|-----------|-----------|-------|
| 1.1 | RLS Enabled | ⬜ | |
| 1.2 | Functions Exist | ⬜ | |
| 1.3 | Triggers Active | ⬜ | |
| 2.1 | Create Family | ⬜ | |
| 2.2 | Join Family | ⬜ | |
| 3.1 | Activity Logging | ⬜ | |
| 3.2 | Activity Editing | ⬜ | |
| 3.3 | Activity Deletion | ⬜ | |
| 4.1 | Create Reminder | ⬜ | |
| 4.2 | Complete Reminder | ⬜ | |
| 4.3 | Edit Reminder | ⬜ | |
| 5.1 | View Members | ⬜ | |
| 5.2 | Remove Member | ⬜ | |
| 5.3 | Leave Family | ⬜ | |
| 6.1 | Generate Code | ⬜ | |
| 6.2 | Code Expiration | ⬜ | |
| 6.3 | Invalid Code | ⬜ | |
| 6.4 | Revoke Invite | ⬜ | |
| 7.1 | Connection | ⬜ | |
| 7.2 | Rapid Changes | ⬜ | |
| 7.3 | Concurrent Edit | ⬜ | |
| 8.1 | Unauthorized | ⬜ | |
| 8.2 | Removed Access | ⬜ | |
| 8.3 | Non-Creator Perms | ⬜ | |
| 9.1 | Last Member | ⬜ | |
| 9.2 | Multiple Families | ⬜ | |
| 9.3 | Deleted Dog | ⬜ | |
| 10.1 | Large Family | ⬜ | |
| 10.2 | Many Activities | ⬜ | |
```

## Automated Testing (Future)

Consider adding XCTest cases for:
- SupabaseManager family functions
- RLS policy enforcement
- Realtime connection handling
- Invite code validation
- Member management logic

## Reporting Issues

If tests fail, collect:
1. Test ID and description
2. Steps to reproduce
3. Expected vs actual result
4. Supabase logs (Dashboard → Logs)
5. Xcode console output
6. Device/iOS version

---

**Happy Testing!** 🧪

