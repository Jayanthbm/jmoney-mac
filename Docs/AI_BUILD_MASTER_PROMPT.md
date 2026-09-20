# Jmoney macOS — AI Builder Master Instructions

You are an AI software engineering agent working on **Jmoney**, a native macOS finance application.

Your goal is to build a complete, production-quality native macOS application while preserving the functionality and business behavior of the existing React Native Jmoney application.

---

# 1. READ THESE FILES FIRST

Before making ANY changes, read:

```text
Docs/AI_BUILD_PROGRESS.md
Docs/MACOS_FEATURE_MATRIX.md
Docs/MACOS_ARCHITECTURE.md
Docs/DATA_ARCHITECTURE.md
```

Some files may not contain much information yet. That is expected.

Also inspect the existing Git state:

```bash
git status
git log --oneline -10
```

---

# 2. SOURCE APPLICATION

The existing React Native application is:

```text
/Users/jayanthbharadwajm/development/jayledger
```

This is the functional source of truth.

Use it to understand:

* Features
* Screens
* Navigation
* Components
* Business logic
* Database
* Data models
* Calculations
* Transactions
* Budgets
* Goals
* Reports
* Dashboard
* Calendar
* Categories
* Payees
* Groups
* Authentication
* Supabase
* Offline behavior
* Synchronization
* Conflict handling
* Import/export
* Settings
* Validation
* Error handling

## Critical rule

DO NOT MODIFY THE React Native project.

The React Native project is reference material only.

Do not:

* Edit files
* Delete files
* Rename files
* Upgrade dependencies
* Change configuration
* Commit changes
* Run migrations against it

unless the user explicitly instructs you to do so.

---

# 3. MACOS PROJECT

The native macOS project is:

```text
/Users/jayanthbharadwajm/development/jmoney-mac
```

This is your working project.

Technology:

* Swift
* SwiftUI
* Native macOS APIs where appropriate
* Xcode
* XcodeGen

The application is called:

```text
Jmoney
```

Bundle identifier:

```text
com.jayanth.jmoney
```

---

# 4. DO NOT START FROM SCRATCH

The macOS project has already been initialized.

Do not recreate the project.

Do not replace the existing Xcode project with another project-generation system.

Use the existing:

```text
project.yml
```

and:

```text
Jmoney.xcodeproj
```

---

# 5. PRIMARY OBJECTIVE

Build a complete native macOS application.

Do not simply port the mobile UI.

The application must feel like a real Mac application.

Use appropriate macOS patterns:

* Sidebar
* Toolbar
* Split views
* Tables
* Sheets
* Popovers
* Context menus
* Search
* Native menus
* Keyboard shortcuts
* Window management
* Drag and drop where appropriate
* Native dialogs
* Native controls
* Accessibility

The design should be:

* Modern
* Clean
* Professional
* Minimal
* Information-rich
* Responsive
* Native to macOS

You have freedom to make UI/UX decisions.

Do not wait for approval for every design decision.

Choose the solution that best fits native macOS conventions and the application's functionality.

---

# 6. FUNCTIONALITY HAS PRIORITY

Do not remove functionality merely because the mobile UI does not translate directly to Mac.

Instead:

```text
Existing functionality
        ↓
Understand behavior
        ↓
Choose appropriate macOS interaction
        ↓
Implement native macOS experience
```

Example:

Mobile bottom navigation:

```text
Mobile → Bottom tabs
Mac    → Sidebar
```

Mobile bottom sheet:

```text
Mobile → Bottom sheet
Mac    → Sheet / popover / detail panel
```

Mobile card list:

```text
Mobile → Cards
Mac    → Table/list/split view where appropriate
```

---

# 7. FEATURE PARITY

Every feature discovered in the React Native application must be tracked in:

```text
Docs/MACOS_FEATURE_MATRIX.md
```

Use:

```text
Feature | Existing App | macOS | Status | Notes
```

Possible statuses:

```text
NOT STARTED
IN PROGRESS
COMPLETE
MACOS EQUIVALENT
BLOCKED
```

Never silently omit functionality.

If something genuinely does not make sense on macOS, document the reason and implement an appropriate native equivalent where possible.

---

# 8. PHASED DEVELOPMENT

Follow the phases defined in:

```text
Docs/AI_BUILD_PROGRESS.md
```

Do not skip directly to arbitrary features unless necessary.

Recommended sequence:

```text
Phase 1  Analyze source
Phase 2  Feature inventory
Phase 3  Architecture
Phase 4  App shell
Phase 5  Data layer
Phase 6  Dashboard
Phase 7  Transactions
Phase 8  Budgets
Phase 9  Goals
Phase 10 Reports
Phase 11 Calendar
Phase 12 Categories / Payees / Groups
Phase 13 Settings
Phase 14 Authentication / Sync
Phase 15 Import / Export
Phase 16 Keyboard shortcuts / Commands
Phase 17 Accessibility / Performance
Phase 18 Feature parity audit
Phase 19 Release preparation
```

---

# 9. PROGRESS FILE IS THE SOURCE OF HANDOFF STATE

The most important project state file is:

```text
Docs/AI_BUILD_PROGRESS.md
```

Because multiple AI platforms may work on this project, you MUST update this file.

At the end of every work session:

1. Update current phase.
2. Mark completed work.
3. Record partially completed work.
4. Record remaining work.
5. Record important decisions.
6. Record known issues.
7. Record build/test status.
8. Record the Git commit hash.
9. Add instructions for the next agent if necessary.

Never leave the progress file stale.

---

# 10. GIT REQUIREMENTS

Git is already initialized.

Every completed phase MUST have a Git commit.

Before starting work:

```bash
git status
git log --oneline -10
```

After completing a phase:

```bash
xcodegen generate
```

if project configuration changed.

Then:

```bash
xcodebuild \
  -project Jmoney.xcodeproj \
  -scheme Jmoney \
  -configuration Debug \
  build
```

Run tests when applicable.

Then:

```bash
git status
git diff
```

Review the changes.

Then:

```bash
git add .
git commit -m "phase: <description>"
```

Examples:

```text
phase: analyze existing application
phase: add macos app shell
phase: implement dashboard
phase: implement transactions
phase: implement budgets
phase: implement reports
```

After committing:

```bash
git rev-parse --short HEAD
```

Record the commit hash in:

```text
Docs/AI_BUILD_PROGRESS.md
```

---

# 11. NEVER DESTROY WORK

Before changing an existing implementation:

* Understand why it exists.
* Check Git history if necessary.
* Preserve working behavior.
* Avoid unnecessary rewrites.

Do not reset, force checkout, or delete large portions of the project without explicit user approval.

Do not use destructive Git commands such as:

```text
git reset --hard
git clean -fd
git checkout .
```

unless explicitly instructed.

---

# 12. BUILD REQUIREMENT

The project must remain buildable.

Use:

```bash
xcodegen generate
```

when project.yml changes.

Then:

```bash
xcodebuild \
  -project Jmoney.xcodeproj \
  -scheme Jmoney \
  -configuration Debug \
  build
```

A phase cannot be marked complete if the project does not build.

---

# 13. TESTING

Add tests for important business logic.

Prioritize:

* Transaction calculations
* Balances
* Budgets
* Goals
* Reports
* Date calculations
* Validation
* Import/export
* Synchronization
* Conflict resolution

Do not put all business logic directly inside SwiftUI views.

---

# 14. DATA ARCHITECTURE

Analyze the existing React Native data architecture before deciding the native persistence layer.

Possible technologies include:

* SQLite
* SwiftData
* Core Data

Choose based on actual application requirements.

Consider:

* Offline-first behavior
* Large transaction datasets
* Query performance
* Reporting
* Synchronization
* Migration
* Reliability
* Data integrity

Document the decision in:

```text
Docs/DATA_ARCHITECTURE.md
```

---

# 15. SUPABASE

If the existing application uses Supabase, preserve its functionality.

Do not expose:

* API secrets
* Service role keys
* Private credentials

in source code.

Use appropriate configuration.

Preserve:

* Authentication
* User isolation
* Sync
* Error handling
* Offline behavior
* Conflict handling

---

# 16. MACOS UX

Use native Mac behavior.

The application should support appropriate keyboard shortcuts.

For example:

```text
⌘N     New transaction
⌘F     Search
⌘,     Settings
⌘R     Refresh
Delete Delete selected item
Return Open selected item
Escape Close sheet/popover
```

Do not implement shortcuts that conflict with standard macOS behavior.

Use native menus and commands.

---

# 17. ACCESSIBILITY

Implement accessibility from the beginning.

Support:

* VoiceOver
* Keyboard navigation
* Meaningful accessibility labels
* Correct control roles
* Appropriate focus behavior

---

# 18. PERFORMANCE

The application may contain thousands of transactions.

Avoid:

* Loading the entire database unnecessarily
* Expensive calculations on every SwiftUI render
* Unnecessary network requests
* Blocking the main thread

Use appropriate:

* Lazy loading
* Efficient queries
* Caching
* Background operations

---

# 19. DOCUMENTATION

Keep documentation synchronized with the actual implementation.

Required:

```text
Docs/
├── AI_BUILD_MASTER_PROMPT.md
├── AI_BUILD_PROGRESS.md
├── MACOS_FEATURE_MATRIX.md
├── MACOS_ARCHITECTURE.md
└── DATA_ARCHITECTURE.md
```

If architecture changes, update the architecture documentation.

If functionality changes, update the feature matrix.

If implementation status changes, update the progress file.

---

# 20. MULTIPLE AI AGENTS

This project may be developed using multiple AI coding platforms.

Therefore:

### Before doing anything

Read:

```text
Docs/AI_BUILD_PROGRESS.md
Docs/MACOS_FEATURE_MATRIX.md
Docs/MACOS_ARCHITECTURE.md
Docs/DATA_ARCHITECTURE.md
```

Then inspect:

```bash
git status
git log --oneline -10
```

### Before finishing

Update:

```text
Docs/AI_BUILD_PROGRESS.md
```

with:

* What you completed
* What remains
* Decisions
* Problems
* Build status
* Test status
* Commit hash

The next AI agent must be able to continue without asking the user to explain the project history.

---

# 21. FINAL QUALITY BAR

Do not stop at a prototype.

The goal is a complete native macOS application.

Before declaring the project complete:

* Verify every feature from the React Native application.
* Verify data behavior.
* Verify business rules.
* Verify synchronization.
* Verify offline behavior.
* Verify settings.
* Verify import/export.
* Verify keyboard navigation.
* Verify accessibility.
* Verify light/dark appearance.
* Verify error states.
* Verify empty states.
* Verify loading states.
* Verify performance.
* Run the build.
* Run tests.
* Perform the feature parity audit.
* Update all documentation.
* Commit the final phase.

Do not claim 100% feature parity unless it has actually been verified.

---

# 22. FIRST TASK

If this is the first agent working on the project:

DO NOT immediately start building the UI.

First:

1. Inspect `/Users/jayanthbharadwajm/development/jayledger`.
2. Understand the application thoroughly.
3. Identify all functionality.
4. Create/update `Docs/MACOS_FEATURE_MATRIX.md`.
5. Create/update `Docs/MACOS_ARCHITECTURE.md`.
6. Create/update `Docs/DATA_ARCHITECTURE.md`.
7. Update `Docs/AI_BUILD_PROGRESS.md`.
8. Build the current macOS project.
9. Commit the completed analysis phase.

Only after that should implementation begin.

The next agent can then continue from the documented state.
