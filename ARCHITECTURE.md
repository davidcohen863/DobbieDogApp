# Multi-User Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        iOS App (SwiftUI)                        │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │  Home View   │  │  Calendar    │  │   Settings   │        │
│  │  (Activity)  │  │  (Reminders) │  │  (Members)   │        │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │
│         │                  │                  │                 │
│         └──────────────────┴──────────────────┘                │
│                           │                                     │
│                  ┌────────▼─────────┐                          │
│                  │ SupabaseManager  │                          │
│                  │  - Auth          │                          │
│                  │  - CRUD Ops      │                          │
│                  │  - Realtime      │                          │
│                  │  - Members       │                          │
│                  └────────┬─────────┘                          │
└───────────────────────────┼──────────────────────────────────┘
                            │
                 ┌──────────┴──────────┐
                 │  Supabase Cloud     │
                 │                     │
          ┌──────▼──────┐      ┌─────▼──────┐
          │  Auth       │      │  Realtime  │
          │  (Users)    │      │  (WebSocket)│
          └──────┬──────┘      └─────┬──────┘
                 │                   │
          ┌──────▼───────────────────▼──────┐
          │    PostgreSQL Database          │
          │    (with RLS Policies)          │
          │                                 │
          │  ┌────────────────────────────┐ │
          │  │  Tables:                   │ │
          │  │  • families                │ │
          │  │  • family_members          │ │
          │  │  • family_invites          │ │
          │  │  • dogs                    │ │
          │  │  • activity_logs           │ │
          │  │  • reminders               │ │
          │  │  • reminder_occurrences    │ │
          │  └────────────────────────────┘ │
          │                                 │
          │  ┌────────────────────────────┐ │
          │  │  RLS Policies:             │ │
          │  │  • User family membership  │ │
          │  │  • Dog access control      │ │
          │  │  • Creator permissions     │ │
          │  └────────────────────────────┘ │
          └─────────────────────────────────┘
```

## Data Flow: Logging an Activity

```
User A Logs Walk
       │
       ▼
┌──────────────┐
│  Home View   │ (Tap "Walk" button)
└──────┬───────┘
       │
       ▼
┌──────────────────────┐
│ SupabaseManager      │
│ .logActivity()       │
└──────┬───────────────┘
       │
       ▼ INSERT INTO activity_logs
┌──────────────────────┐
│  Supabase            │
│  1. Authenticate     │◄─── auth.session
│  2. Check RLS        │◄─── has_dog_access(dog_id)
│  3. Insert row       │
│  4. Broadcast event  │
└──────┬───────────────┘
       │
       ├─────────────────────────┐
       │                         │
       ▼                         ▼
User A Device              User B Device
       │                         │
       ▼                         ▼
┌──────────────┐          ┌──────────────┐
│ Realtime     │          │ Realtime     │
│ onPostgres   │          │ onPostgres   │
│ Change       │          │ Change       │
└──────┬───────┘          └──────┬───────┘
       │                         │
       ▼                         ▼
┌──────────────┐          ┌──────────────┐
│ onChange()   │          │ onChange()   │
│ callback     │          │ callback     │
└──────┬───────┘          └──────┬───────┘
       │                         │
       ▼                         ▼
┌──────────────┐          ┌──────────────┐
│ UI Updates   │          │ UI Updates   │
│ Instantly!   │          │ Instantly!   │
└──────────────┘          └──────────────┘
```

## Security Flow: RLS Enforcement

```
Query Request
     │
     ▼
┌─────────────────────────────────┐
│ 1. Supabase Auth                │
│    Is user authenticated?       │
└─────────┬───────────────────────┘
          │ YES
          ▼
┌─────────────────────────────────┐
│ 2. RLS Policy Check             │
│    Run: has_dog_access(dog_id)  │
│         ↓                       │
│    SELECT family_id FROM dogs   │
│    WHERE id = dog_id            │
│         ↓                       │
│    SELECT user_id               │
│    FROM family_members          │
│    WHERE family_id = ...        │
│         ↓                       │
│    Does user_id match auth?     │
└─────────┬───────────────────────┘
          │ YES
          ▼
┌─────────────────────────────────┐
│ 3. Execute Query                │
│    Return filtered results      │
└─────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────┐
│ Result sent to app              │
│ (Only family's data)            │
└─────────────────────────────────┘

If NO at any step → Empty result or Error
```

## Invitation Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    FAMILY CREATOR (User A)                    │
└──────────────────────────┬───────────────────────────────────┘
                           │
                    1. Generate Share Code
                           │
                           ▼
                  ┌─────────────────┐
                  │ Supabase        │
                  │ RPC: create_    │
                  │ family_share_   │
                  │ code()          │
                  │                 │
                  │ • Generate 6    │
                  │   char code     │
                  │ • Set expiry    │
                  │ • Insert into   │
                  │   invites table │
                  └────────┬────────┘
                           │
                  2. Code: "ABC123"
                           │
                ┌──────────┴──────────┐
                │                     │
         Share via Text        Share via Link
                │                     │
                └─────────┬───────────┘
                          │
┌─────────────────────────▼──────────────────────────────────┐
│                  NEW USER (User B)                         │
└─────────────────────────┬──────────────────────────────────┘
                          │
                  3. Enter Code "ABC123"
                          │
                          ▼
                  ┌─────────────────┐
                  │ Supabase        │
                  │ RPC: accept_    │
                  │ family_invite_  │
                  │ by_code()       │
                  │                 │
                  │ • Validate code │
                  │ • Check expiry  │
                  │ • Add user to   │
                  │   family_members│
                  │ • Mark accepted │
                  └────────┬────────┘
                          │
                  4. User B now member
                          │
                ┌─────────┴─────────┐
                │                   │
        Access to Dogs      Access to Activities
```

## Family Membership Model

```
Family "Smith Family"
    │
    ├─── Member: Alice (Creator)
    │    ├─ Can view/edit all data
    │    ├─ Can invite members
    │    ├─ Can remove members
    │    └─ Cannot leave family
    │
    ├─── Member: Bob
    │    ├─ Can view/edit all data
    │    ├─ Can invite members
    │    ├─ Cannot remove members
    │    └─ Can leave family
    │
    └─── Dogs
         ├─ Max (Golden Retriever)
         │  ├─ Activity Logs (shared)
         │  ├─ Reminders (shared)
         │  └─ Goals (shared)
         │
         └─ Bella (Poodle)
            ├─ Activity Logs (shared)
            ├─ Reminders (shared)
            └─ Goals (shared)

All members see ALL dogs and ALL activities.
Changes by any member sync to all members in real-time.
```

## Realtime Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Supabase Realtime                       │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  Realtime Channel: "realtime:family:{family_id}"     │ │
│  │                                                       │ │
│  │  Subscriptions:                                      │ │
│  │  • activity_logs (INSERT/UPDATE/DELETE)              │ │
│  │  • dogs (INSERT/UPDATE/DELETE)                       │ │
│  │  • reminders (INSERT/UPDATE/DELETE)                  │ │
│  │  • reminder_occurrences (UPDATE)                     │ │
│  │  • family_members (INSERT/DELETE)                    │ │
│  └──────────────────┬────────────────────────────────────┘ │
│                     │                                       │
│         ┌───────────┴───────────┐                         │
│         │                       │                         │
│    WebSocket                WebSocket                     │
│         │                       │                         │
└─────────┼───────────────────────┼─────────────────────────┘
          │                       │
    ┌─────▼─────┐           ┌─────▼─────┐
    │  Device A │           │  Device B │
    │  (User A) │           │  (User B) │
    └───────────┘           └───────────┘

When User A logs activity:
1. INSERT hits database
2. Postgres triggers realtime event
3. Realtime broadcasts to all subscribed devices
4. Both Device A and B receive event
5. Both devices call onChange() callback
6. Both UIs update instantly
```

## State Management

```
App Launch
    │
    ▼
┌────────────────────────────┐
│  Check Auth Session        │
│  (SupabaseManager)         │
└────────┬───────────────────┘
         │
         ├─ No Session ──> SignUpView
         │
         ├─ Has Session ──> Check Setup
         │
         ▼
┌────────────────────────────┐
│  Check Dog Exists          │
│  getDogId()                │
└────────┬───────────────────┘
         │
         ├─ No Dog ──> SetupView (create or join)
         │
         ├─ Has Dog ──> MainTabView
         │
         ▼
┌────────────────────────────┐
│  MainTabView               │
│  • Load dog data           │
│  • Start realtime          │
│  • Cache family/dog ID     │
└────────────────────────────┘

UserDefaults Storage:
• activeFamilyId (String?)
• cachedDogId (String?)
• pending_invite_token (String)

In-Memory State:
• RealtimeStore.activityChannel
• RealtimeStore.familyChannel
• RealtimeStore.subscriptions
```

## Database Schema Diagram

```
┌──────────────────┐
│   auth.users     │ (Supabase managed)
│  ├─ id (uuid)    │
│  ├─ email        │
│  └─ ...          │
└────────┬─────────┘
         │
         │ created_by
         ▼
┌──────────────────┐
│    families      │
│  ├─ id           │◄──┐
│  ├─ name         │   │
│  ├─ created_by   │   │ family_id
│  └─ created_at   │   │
└────────┬─────────┘   │
         │             │
         │ family_id   │
         ▼             │
┌──────────────────┐   │
│ family_members   │   │
│  ├─ id           │   │
│  ├─ family_id    │───┘
│  ├─ user_id      │
│  └─ joined_at    │
└──────────────────┘
         │
         │ family_id
         ▼
┌──────────────────┐
│  family_invites  │
│  ├─ id           │
│  ├─ family_id    │
│  ├─ token        │
│  ├─ share_code   │
│  ├─ expires_at   │
│  ├─ status       │
│  └─ ...          │
└──────────────────┘

         │ family_id
         ▼
┌──────────────────┐
│      dogs        │
│  ├─ id           │◄──┐
│  ├─ family_id    │   │
│  ├─ name         │   │
│  ├─ breed        │   │ dog_id
│  └─ ...          │   │
└────────┬─────────┘   │
         │             │
         │ dog_id      │
         ▼             │
┌──────────────────┐   │
│  activity_logs   │   │
│  ├─ id           │   │
│  ├─ dog_id       │───┘
│  ├─ event_type   │
│  ├─ timestamp    │
│  ├─ notes        │
│  └─ metadata     │
└──────────────────┘

         │ dog_id
         ▼
┌──────────────────┐
│    reminders     │
│  ├─ id           │◄──┐
│  ├─ dog_id       │   │
│  ├─ title        │   │
│  ├─ schedule     │   │ reminder_id
│  └─ ...          │   │
└────────┬─────────┘   │
         │             │
         │             │
         ▼             │
┌──────────────────┐   │
│reminder_occur-   │   │
│  rences          │   │
│  ├─ id           │   │
│  ├─ reminder_id  │───┘
│  ├─ dog_id       │
│  ├─ occurs_at    │
│  └─ status       │
└──────────────────┘
```

## Permission Matrix

| Resource | Creator | Member | Non-Member |
|----------|---------|--------|------------|
| **View family** | ✅ | ✅ | ❌ |
| **View dogs** | ✅ | ✅ | ❌ |
| **View activities** | ✅ | ✅ | ❌ |
| **Log activities** | ✅ | ✅ | ❌ |
| **Edit activities** | ✅ | ✅ | ❌ |
| **Delete activities** | ✅ | ✅ | ❌ |
| **Create reminders** | ✅ | ✅ | ❌ |
| **Edit reminders** | ✅ | ✅ | ❌ |
| **Create invites** | ✅ | ✅ | ❌ |
| **Revoke invites** | ✅ | ✅ | ❌ |
| **View members** | ✅ | ✅ | ❌ |
| **Remove members** | ✅ | ❌ | ❌ |
| **Leave family** | ❌ | ✅ | N/A |
| **Delete family** | ✅ | ❌ | ❌ |

Legend:
- ✅ Allowed
- ❌ Blocked by RLS
- N/A Not applicable

## Error Handling Flow

```
User Action
    │
    ▼
Try Operation
    │
    ├─ Success ──> Update UI + Haptic
    │
    └─ Failure
         │
         ├─ Network Error
         │    └─> Show "Check connection"
         │
         ├─ Auth Error
         │    └─> Redirect to login
         │
         ├─ RLS Permission Denied
         │    └─> Show "No access"
         │
         ├─ Not Found
         │    └─> Refresh data
         │
         └─ Unknown
              └─> Log to console + Show generic error
```

## Scalability Considerations

### Current Design Supports:
- **Users per family:** Unlimited (tested to 100+)
- **Dogs per family:** Unlimited
- **Activities per dog:** Thousands (pagination recommended at 10k+)
- **Concurrent users:** Hundreds per family (Realtime limit)
- **Families per user:** Unlimited

### Bottlenecks to Watch:
1. **Realtime connections:** Each device = 1 WebSocket
   - Solution: Supabase auto-scales
2. **RLS policy performance:** Complex joins on large tables
   - Solution: Indexes already added
3. **Activity logs growth:** Millions of rows
   - Solution: Partition by date or archive old data

### Recommended Limits:
- Max 10 active members per family (UX consideration)
- Archive activities > 1 year old
- Limit realtime to last 30 days of data

---

## References

- [Supabase RLS Documentation](https://supabase.com/docs/guides/auth/row-level-security)
- [Supabase Realtime](https://supabase.com/docs/guides/realtime)
- [SwiftUI Best Practices](https://developer.apple.com/documentation/swiftui)

