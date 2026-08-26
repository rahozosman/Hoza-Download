# Hoza Download — Claude Code Engineering & Quality Rules

> Companion rules for the main `CLAUDE.md`.
> This file intentionally focuses on engineering practices, product quality, debugging, UI quality, state management, releases, and maintainability that are not already covered by the main rules.

---

## 1. PLAN BEFORE EDITING

Before making meaningful changes:

1. Understand the requested outcome.
2. Inspect the current implementation.
3. Identify dependencies and affected screens/services.
4. Decide the smallest implementation that solves the problem.
5. Make the changes in logical batches.
6. Verify each meaningful batch before moving on.

Do not start editing immediately when the architecture or existing behavior is unclear.

For complex work, maintain a short internal plan:

- What exists?
- What must change?
- What files are likely affected?
- What could break?
- How will the result be verified?

Do not spend tokens explaining the entire plan unless the user asks.

---

## 2. PRESERVE EXISTING BEHAVIOR

A new feature must not silently break existing features.

Before changing shared code, determine:

- Who uses it?
- What inputs does it expect?
- What outputs does it provide?
- Which screens depend on it?
- Are there platform-specific behaviors?

When replacing an implementation:

- preserve public behavior where possible
- migrate callers safely
- remove obsolete code only after the replacement works
- verify affected flows

Never solve one screen's problem by damaging another screen.

---

## 3. SOURCE OF TRUTH

Every important piece of state should have one clear source of truth.

Avoid:

- duplicated state
- manually synchronized copies
- conflicting controllers
- UI state pretending to be business state
- values stored in multiple unrelated places

When the same value appears in several places, determine whether those are views of one state rather than separate states.

Prefer:

`UI → controller/provider → service/repository → data source`

Do not make widgets responsible for coordinating complex business state.

---

## 4. ASYNC AND LIFECYCLE SAFETY

Flutter code must safely handle asynchronous operations.

Before calling `setState` after an async operation, ensure the widget is still mounted.

Do not:

- update disposed controllers
- use disposed contexts
- leave subscriptions running after disposal
- start duplicate listeners
- create timers that never stop
- start background work without a cancellation strategy

Every subscription, timer, animation controller, stream listener, and disposable resource must have a clear lifecycle.

For long-running downloads, make cancellation explicit and safe.

---

## 5. STATE TRANSITIONS MUST BE EXPLICIT

Important operations should have predictable states.

For example:

`idle → preparing → downloading → completed`

or:

`idle → preparing → failed`

Do not allow contradictory states such as:

- completed + downloading
- cancelled + actively downloading
- failed + indefinite loading

When state changes, update all dependent UI consistently.

Centralize state transitions when the operation is complex.

---

## 6. UI MUST REPRESENT REAL STATE

The interface must never claim something happened when it did not.

Examples:

- Do not show 100% unless the download actually completed.
- Do not show "Saved" before the file is successfully saved.
- Do not show "Paused" while the operation is still active.
- Do not show success after an API/storage failure.
- Do not display fake progress to make the interface look active.

Animations may improve perception, but they must never replace real state.

---

## 7. LOADING UX

Every asynchronous screen or operation needs intentional loading behavior.

Use:

- immediate visual feedback
- meaningful progress where available
- disabled actions when necessary
- cancellation where appropriate
- clear error recovery

Avoid:

- infinite spinners
- blocking the entire screen unnecessarily
- flashing loading states for extremely short operations
- restarting the loading animation because of unrelated rebuilds

Prefer skeletons or localized loading indicators when only part of the screen is loading.

---

## 8. EMPTY STATES

Every list or content area should intentionally handle the empty case.

An empty state should answer:

1. What is empty?
2. Why might it be empty?
3. What can the user do next?

Examples:

- No downloads yet
- No completed files
- No supported link detected

Do not leave large blank spaces without explanation.

---

## 9. ERROR UX

Errors should be useful to users and developers.

User-facing errors should:

- be understandable
- avoid technical jargon where unnecessary
- explain what happened
- provide a recovery action when possible

Prefer:

`Download failed — Check your connection and try again.`

over:

`SocketException: OS Error 11001`

Technical details may be logged safely for debugging, but sensitive information must never be exposed.

---

## 10. RETRY DESIGN

Retry must not blindly repeat the same failed operation forever.

Before retrying:

- determine whether retry makes sense
- reset stale state
- avoid duplicate downloads
- avoid duplicate requests
- preserve user intent

Use bounded retries for transient network failures when appropriate.

Do not retry permanent failures repeatedly.

---

## 11. NETWORKING

Treat all network responses as unreliable.

Handle:

- timeout
- connection failure
- invalid response
- unexpected status code
- malformed JSON
- empty response
- server error
- partial response
- cancellation

Never assume:

- the server is available
- JSON has the expected shape
- URLs are valid
- metadata exists
- response sizes are safe

Validate external data before using it.

---

## 12. INPUT VALIDATION

Validate user input at the boundary.

For URLs:

- reject obviously invalid values
- normalize safely where appropriate
- trim accidental whitespace
- avoid trusting query parameters
- reject unsupported schemes

For filenames:

- sanitize unsafe characters
- prevent path traversal
- avoid reserved names
- prevent accidental overwriting unless intended

Never pass untrusted input directly into filesystem, shell, or platform operations.

---

## 13. NO SHELL COMMANDS FROM USER INPUT

Never construct shell commands using raw user-provided values.

If an external process is genuinely required:

- use a safe argument API
- validate every argument
- avoid shell interpretation
- handle process failure
- handle process cancellation
- limit output size

Never execute arbitrary user-provided commands.

---

## 14. FILE SYSTEM SAFETY

Downloaded files are untrusted external data.

Before saving:

1. Validate the destination.
2. Sanitize the filename.
3. Confirm the target directory.
4. Check available storage where practical.
5. Handle existing files intentionally.
6. Write safely.
7. Confirm the final file exists and is usable.

Never allow a URL or server-provided filename to choose an arbitrary filesystem path.

---

## 15. MEMORY AND LARGE FILES

Downloads can be large.

Do not unnecessarily load entire videos, audio files, or responses into memory.

Prefer:

- streaming
- chunked processing
- temporary files
- bounded buffers

Avoid converting large files to giant byte arrays unless absolutely necessary.

Monitor memory-sensitive operations carefully.

---

## 16. UI PERFORMANCE

Keep expensive work away from the UI thread.

Watch for:

- large synchronous loops
- expensive JSON parsing
- huge image decoding
- unnecessary rebuilds
- repeated provider computations
- unnecessary list rendering
- expensive filesystem operations during build

Use Flutter performance tools when a real performance problem exists.

Do not optimize blindly.

Measure first when practical.

---

## 17. REBUILD DISCIPLINE

A widget should rebuild because its relevant state changed.

Avoid:

- rebuilding entire pages for small state changes
- placing large stateful sections under rapidly changing providers
- recreating expensive objects during every build
- starting side effects inside `build()`

Never perform network requests, downloads, file writes, or navigation as uncontrolled side effects of `build()`.

---

## 18. WIDGET DESIGN

Keep widgets focused.

A widget should ideally have one clear responsibility.

Extract a widget when:

- it is reused
- it has meaningful independent state
- it makes the parent easier to understand
- it represents a recognizable UI component

Do not extract every three lines into a separate file.

Balance reuse with readability.

---

## 19. RESPONSIVE UI

Do not assume one screen size.

Consider:

- small Android phones
- large phones
- portrait
- landscape when relevant
- system text scaling
- different pixel densities
- navigation/status bar areas

Avoid fixed dimensions when content can vary.

Use constraints, flexible layouts, and appropriate spacing.

Never allow important actions or text to be clipped.

---

## 20. ACCESSIBILITY

A premium interface must remain usable.

Consider:

- readable contrast
- sufficient touch targets
- semantic labels
- meaningful button labels
- icons that are understandable without color alone
- text scaling
- screen reader compatibility where practical

Do not use color as the only indication of success, failure, or state.

---

## 21. ANIMATION RULES

Animations must communicate state or improve navigation.

Good animation:

- fast enough to feel responsive
- subtle
- consistent
- interruptible when appropriate
- tied to real state changes

Avoid:

- animations on every element
- long transitions
- distracting loops
- animations that delay important actions
- animation that hides loading or failure

Respect reduced-motion preferences when the platform/app supports them.

---

## 22. DESIGN SYSTEM CONSISTENCY

Before creating a new UI element, search for an existing equivalent.

Reuse:

- spacing
- typography
- colors
- buttons
- cards
- dialogs
- icons
- loading indicators
- error components

If a new component is necessary, make it consistent with the existing visual language.

Do not create five slightly different versions of the same button.

---

## 23. TYPOGRAPHY

Use a deliberate typography hierarchy.

Define consistent roles such as:

- display
- page title
- section title
- body
- secondary text
- caption
- error/status text

Avoid random font sizes throughout the app.

Do not use excessive font weights or decorative typography that harms readability.

---

## 24. DARK MODE AND CONTRAST

Dark UI should not mean pure black everywhere.

Use a clear hierarchy between:

- background
- elevated surface
- card
- input
- divider
- primary text
- secondary text
- accent

Check contrast for every important action.

Do not rely on very subtle gray text that becomes unreadable on real devices.

---

## 25. LOCALIZATION READINESS

Do not hardcode user-facing strings inside complicated business logic.

Keep text organized so localization can be introduced later.

Avoid layouts that assume every string is short.

Buttons and cards should tolerate longer translated text.

Never use text width as the only layout constraint.

---

## 26. CONFIGURATION AND SECRETS

Never commit:

- API keys
- private tokens
- passwords
- signing credentials
- private certificates
- service-account secrets

Use environment/configuration mechanisms appropriate to the project.

If a secret is accidentally exposed:

1. Stop using it.
2. Remove it from the repository.
3. Rotate/revoke it.
4. Check Git history if necessary.
5. Replace it securely.

Do not merely hide a secret in another source file.

---

## 27. LOGGING

Logs should help debugging without exposing private information.

Good logs identify:

- operation
- safe status
- failure category
- useful diagnostic context

Never log:

- passwords
- access tokens
- authentication headers
- private URLs containing credentials
- sensitive user data

Avoid excessive logs in production.

---

## 28. DATABASE / LOCAL STORAGE

When persistent data is used:

- define models clearly
- validate stored data
- handle missing fields
- handle old data formats
- avoid corrupting existing user data
- keep migrations deliberate

Never assume local storage is always valid.

The app should recover gracefully from partially missing or outdated data.

---

## 29. BACKWARD COMPATIBILITY

When changing stored data, APIs, or shared models:

1. Identify existing data.
2. Consider older app versions.
3. Handle missing/new fields safely.
4. Migrate intentionally if necessary.
5. Test upgrade behavior.

Do not make an update that silently destroys existing user data.

---

## 30. DEPENDENCY UPDATES

Do not update packages just because updates exist.

Before upgrading:

- check compatibility
- inspect breaking changes
- understand why the update is needed
- update the smallest necessary set
- run analysis/tests afterward

Avoid changing many unrelated dependencies during a feature task.

---

## 31. DEBUGGING METHOD

When an error occurs:

1. Read the first meaningful error.
2. Find the file and exact failing operation.
3. Understand why it fails.
4. Reproduce if necessary.
5. Fix the root cause.
6. Verify the fix.
7. Check for nearby regressions.

Do not blindly change random configuration values until the error disappears.

A successful build does not automatically mean the bug is fixed.

---

## 32. ERROR PRIORITY

Prioritize issues in this order:

1. Data loss/security problems
2. Crashes
3. Broken core functionality
4. Incorrect user-visible state
5. Severe performance problems
6. Build/analyzer errors
7. Accessibility problems
8. Minor visual issues
9. Cosmetic cleanup

Do not spend the entire task fixing cosmetic issues while core functionality is broken.

---

## 33. REGRESSION CHECK

After changing an important feature, verify:

- the changed feature
- the most closely related feature
- important navigation
- app startup if initialization changed
- error behavior
- persistence if data changed

Do not test every unrelated screen unless the change is global.

---

## 34. GIT WORKFLOW

Before meaningful work:

```bash
git status
```

After meaningful work:

```bash
git diff
```

Review the diff for:

- accidental changes
- debug code
- secrets
- unrelated formatting
- generated files
- deleted functionality

Before committing, make sure the change is logically complete.

Prefer small, meaningful commits.

Never commit generated secrets or local machine configuration.

---

## 35. COMMIT MESSAGES

Use clear commit messages.

Good:

```text
feat: add shared URL download flow
fix: prevent duplicate download requests
fix: handle insufficient storage
refactor: simplify download state controller
ui: improve download progress card
```

Avoid:

```text
update
changes
fix stuff
new
test
```

The commit should explain what changed.

---

## 36. CI/CD AWARENESS

If GitHub Actions or another CI system exists:

- inspect the existing workflow before modifying it
- preserve working build targets
- avoid duplicating workflows
- keep secrets in CI secret storage
- make failures actionable
- do not hide failing steps

When a CI build fails, identify whether the problem is:

- source code
- dependency
- Flutter version
- Java/Gradle
- Android SDK
- signing
- environment
- workflow configuration

Fix the correct layer.

---

## 37. RELEASE CHECKLIST

Before a real release, verify:

- app builds successfully
- version number is correct
- application ID is correct
- release signing is configured
- no debug-only behavior remains
- no secrets are exposed
- permissions are justified
- downloads work
- sharing URLs works
- cancellation works
- retry works
- storage failures are handled
- important UI states are correct
- app does not crash on startup

Do not declare a release ready based only on `flutter analyze`.

---

## 38. PLATFORM DIFFERENCES

Do not assume Android behavior is identical across:

- Android versions
- manufacturers
- storage configurations
- permission states
- background restrictions

If behavior depends on Android APIs, verify the minimum supported version and current platform behavior.

Keep platform-specific code isolated from general business logic.

---

## 39. DOCUMENT IMPORTANT DECISIONS

Document decisions that future developers genuinely need to understand.

Good documentation explains:

- why a non-obvious architecture was chosen
- why a platform workaround exists
- why a dependency is required
- why a storage strategy is used
- why a limitation exists

Do not document obvious code.

Comments should answer:

**Why is this done this way?**

not:

**What does this line do?**

---

## 40. CHANGE IMPACT CHECK

Before modifying a shared service, model, provider, or utility, ask:

- Does another feature use this?
- Is it public API inside the project?
- Is its behavior relied upon elsewhere?
- Does changing it require migration?

For risky changes, search references before editing.

---

## 41. SAFE REFACTORING

Do not combine a large refactor with an unrelated feature unless necessary.

Prefer:

1. Understand current behavior.
2. Refactor safely.
3. Verify.
4. Implement the feature.
5. Verify again.

Keep diffs understandable.

A smaller understandable change is safer than a huge "cleanup" diff.

---

## 42. STOP CONDITIONS

Stop and ask the user only when continuing would require a decision that materially affects the product or when access/credentials/permissions are genuinely required.

Examples:

- missing API credentials
- unknown product requirement
- destructive migration decision
- legal/platform permission requirement
- irreversible data operation

Do not ask for permission for ordinary engineering decisions.

---

## 43. FINAL QUALITY GATE

Before considering a task complete, ask internally:

- Does it actually work?
- Does it use the real implementation?
- Does it preserve existing behavior?
- Is the state correct?
- Are errors handled?
- Is the UI responsive?
- Is the code maintainable?
- Did I introduce unnecessary dependencies?
- Did I leave debug code or placeholders?
- Did I inspect the final diff?
- Did I verify the relevant flow?

If an answer is "no", fix it before reporting completion when it is safe to do so.

---

## 44. IMPORTANT PRIORITY

When rules conflict, prioritize:

1. User's explicit current request
2. Safety and platform requirements
3. Correctness
4. Existing working behavior
5. Security and privacy
6. Performance
7. Maintainability
8. Visual polish
9. Convenience

Never sacrifice correctness or user data merely to make the code shorter or the UI prettier.

---

## 45. ENGINEERING MINDSET

Act like the engineer responsible for the application after release.

Think about:

- what happens when the network fails
- what happens when storage is full
- what happens when the user taps twice
- what happens when the app is closed during a download
- what happens when data is missing
- what happens on an older device
- what happens after an update
- what happens when the server returns unexpected data

Do not optimize only for the happy path.

Build for real users and real failures.
