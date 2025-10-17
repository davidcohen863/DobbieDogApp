# Dobbie Dog App 🐶

A collaborative dog activity tracker with real-time sync, built with SwiftUI and Supabase.

## Features

### Core Tracking
- 📝 Activity logging (walks, meals, potty, sleep, play)
- 📅 Calendar view with daily details
- ⏰ Smart reminders with multiple schedules
- 📊 Insights and analytics dashboards
- 💬 AI coach for training tips

### Multi-User Collaboration ✨
- 👥 **Family-based sharing** - Multiple users manage the same dog(s)
- 🔄 **Real-time sync** - Changes appear instantly across all devices
- 🔐 **Secure data isolation** - Users only see their family's data
- 🎫 **Easy invitations** - Share via 6-character code or link
- 👮 **Member management** - Add, view, and remove team members

## Tech Stack

- **Frontend:** SwiftUI, iOS 17+
- **Backend:** Supabase (PostgreSQL, Auth, Realtime)
- **Architecture:** MVVM pattern
- **Security:** Row-Level Security (RLS) policies

## Getting Started

### Prerequisites
- Xcode 15+
- iOS 17+ device or simulator
- Supabase account

### Installation

1. **Clone the repository**
```bash
git clone <your-repo-url>
cd DobbieDogApp
```

2. **Configure Supabase**
   - Open `SupabaseManager.swift`
   - Update `baseURL` and `supabaseKey` with your project credentials

3. **Enable Multi-User (IMPORTANT)**
   
   Follow the [Quick Start Guide](QUICK_START.md) (5 minutes) or the comprehensive [Multi-User Setup Guide](MULTI_USER_SETUP.md).

   **TL;DR:**
   - Run SQL migrations in `supabase_migrations/`
   - Enable Realtime on key tables
   - Test with 2 devices

4. **Build and Run**
   - Open `Dobbie Sign Up.xcodeproj` in Xcode
   - Select your target device
   - Press ⌘R to build and run

## Project Structure

```
Dobbie Sign Up/
├── SupabaseManager.swift       # Database & auth logic
├── Models.swift                 # Data models
├── MainTabView.swift            # Root tab navigation
├── Home Screen.swift            # Activity feed
├── CalendarView.swift           # Calendar & reminders
├── SettingsView.swift           # Family & member management
├── SetupView.swift              # Onboarding & join flow
├── ChatView.swift               # AI coach
└── DashboardManager.swift       # Analytics

supabase_migrations/
├── 00_schema_requirements.sql   # Database schema
└── 01_rls_policies.sql          # Security policies
```

## Multi-User Documentation

| Document | Purpose |
|----------|---------|
| [QUICK_START.md](QUICK_START.md) | Get multi-user working in 5 minutes |
| [MULTI_USER_SETUP.md](MULTI_USER_SETUP.md) | Comprehensive setup and troubleshooting |
| [TESTING_GUIDE.md](TESTING_GUIDE.md) | Test all collaboration features |

## Usage

### For Solo Users
1. Create account
2. Set up your dog profile
3. Start logging activities
4. View insights and trends

### For Families/Teams
1. **First user:**
   - Create account
   - Set up dog profile
   - Settings → Generate share code
   - Share code with family

2. **Additional members:**
   - Create account
   - Toggle "Join existing family"
   - Enter share code
   - Start collaborating!

3. **Real-time collaboration:**
   - All members see updates instantly
   - Anyone can log activities
   - Everyone can create reminders
   - Creator can manage members

## Key Features Explained

### Activity Logging
- Quick-tap icons for common activities
- Detailed editing with notes and metadata
- Walk tracking with duration, distance, calories
- Sleep tracking with start/end times

### Smart Reminders
- Multiple schedule types: daily, weekly, interval, monthly
- Timezone-aware firing
- Local notifications
- Completion tracking

### Family Management
- Create/join families via share codes
- View all members and their emails
- Remove members (creators only)
- Leave family (members only)
- Switch between multiple families

### Real-time Sync
- Activity logs sync instantly
- Reminder updates propagate immediately
- Member changes reflected in real-time
- Works across iOS devices

## Security & Privacy

### Row-Level Security (RLS)
All data is protected by Supabase RLS policies:
- Users only see data for families they're in
- Removed members lose access immediately
- Creators have additional permissions
- Direct database access is blocked

### Data Isolation
- Families are completely isolated
- No cross-family data leakage
- SQL-level enforcement via RLS
- Validated by automated policies

## Troubleshooting

### "No dog profile found"
→ Join a family via share code, or create your first dog

### "Permission denied"
→ Check that RLS policies are applied (see setup guide)

### Realtime not working
→ Enable Realtime on tables in Supabase Dashboard

### Can't see other user's activities
→ Verify both users are in the same family

See [MULTI_USER_SETUP.md](MULTI_USER_SETUP.md) for detailed troubleshooting.

## Development

### Adding New Features

1. **New activity type:**
   - Add case to event types in `Models.swift`
   - Update UI in `Home Screen.swift`
   - Add icon to activity picker

2. **New reminder schedule:**
   - Update `schedule_type` in reminder models
   - Add case to `expandOccurrences()` in SupabaseManager
   - Add UI option in `AddReminderSheet.swift`

3. **New collaboration feature:**
   - Add database table/column
   - Create RLS policies
   - Add Realtime subscription
   - Update UI

### Running Tests

```bash
# Unit tests (if available)
xcodebuild test -scheme "Dobbie Sign Up" -destination 'platform=iOS Simulator,name=iPhone 15'

# Manual testing
# Follow TESTING_GUIDE.md for comprehensive test suite
```

## Roadmap

- [ ] Push notifications for family activity
- [ ] Activity comments and reactions
- [ ] Multiple dogs per family
- [ ] Photo albums per dog
- [ ] Export data to CSV/PDF
- [ ] Apple Health integration
- [ ] Offline support with sync queue
- [ ] Role-based permissions (owner/admin/member)

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

[Add your license here]

## Support

For questions or issues:
- Check the [Multi-User Setup Guide](MULTI_USER_SETUP.md)
- Review the [Testing Guide](TESTING_GUIDE.md)
- Check Supabase logs for detailed errors
- Open an issue on GitHub

## Acknowledgments

- Supabase for backend infrastructure
- SwiftUI for beautiful UI framework
- The dog owner community for feedback

---

**Made with ❤️ for dog lovers everywhere** 🐕
