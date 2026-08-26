Hoza Download — Claude Code Rules

1. PRIMARY GOAL

Build and maintain the real Hoza Download Flutter Android application.

This is a REAL PROJECT, not a tutorial, mockup, prototype, or code-generation exercise.

Prioritize:

1. Working functionality
2. Stability
3. Clean UX
4. Performance
5. Maintainability
6. Tests

Do not build unnecessary features.

---

2. WORK ON THE REAL PROJECT

Always inspect the existing project before changing code.

Never recreate the project from scratch unless explicitly requested.

Never replace working code without a reason.

Before editing:

- Inspect relevant files.
- Understand existing architecture.
- Reuse existing components.
- Make the smallest safe change.

Do not generate imaginary files or architecture that does not exist.

---

3. DO NOT LOOP

NEVER repeatedly perform the same action if nothing changed.

If an error remains after two reasonable attempts:

1. Stop.
2. Identify the actual cause.
3. Explain the blocker briefly.
4. Try a different approach.

Do not:

- repeatedly run the same command
- repeatedly rewrite the same file
- repeatedly run tests without changing code
- repeatedly install/uninstall dependencies
- repeatedly regenerate code

Maximum:

2 consecutive attempts for the same unresolved problem.

---

4. TOKEN EFFICIENCY

Be highly token efficient.

Before using a tool:

Ask:

«"Will this actually help me make progress?"»

Do not inspect the entire repository unnecessarily.

Do not print huge files.

Read only relevant sections.

Prefer:

- targeted searches
- targeted file reads
- small patches
- concise summaries

Avoid:

- unnecessary explanations
- repeating code
- repeating project information
- dumping complete files when only a few lines change

When modifying code, prefer a small targeted edit.

---

5. BUILD FIRST, TEST SECOND

The priority is to BUILD THE REAL FEATURE.

Do not spend most of the task writing tests.

For each feature:

1. Implement the feature.
2. Run formatter/analyzer.
3. Run the most relevant test.
4. Fix important errors.
5. Continue development.

Do not create dozens of tests before implementing the feature.

Testing must support development, not replace development.

---

6. TESTING RULES

Use tests strategically.

Always run:

flutter analyze

after meaningful code changes.

Run focused tests when changing important business logic.

Do not repeatedly run the complete test suite after every tiny UI change.

Do not wait for every test to be perfect before continuing development.

If tests fail because of an unrelated existing problem:

- Do not rewrite unrelated code.
- Record the problem.
- Continue with the actual feature if safe.

At the end of a major section, run the relevant test suite.

---

7. NEVER FAKE FUNCTIONALITY

Do not use fake implementations for final features.

Do not create:

- fake downloads
- fake progress
- fake storage
- fake database behavior
- fake Android share functionality

Mock data is allowed ONLY for temporary UI development or automated tests.

Production paths must use real implementations.

---

8. NO PLACEHOLDER FEATURES

Do not leave:

TODO
Coming soon
Implement later
Fake implementation
Placeholder

for functionality that is supposed to be completed in the current section.

If a feature cannot be safely implemented:

Explain why and implement the best safe fallback.

---

9. FEATURE SCOPE

Only implement the feature currently being requested.

Do not randomly add:

- accounts
- login
- cloud sync
- social features
- unnecessary analytics
- unnecessary ads
- unnecessary subscriptions
- unnecessary settings

Keep Hoza Download focused.

---

10. UI/UX RULES

Hoza Download should feel:

- Premium
- Fast
- Clean
- Modern
- Simple

Use:

- dark premium surfaces
- midnight/navy background
- subtle blue accent
- muted green success
- subtle red errors
- rounded cards
- clean typography
- smooth micro-animations

Avoid:

- excessive gradients
- excessive glassmorphism
- giant buttons
- clutter
- unnecessary animations
- excessive colors

Follow the existing design system.

Do not create a new visual system for every screen.

---

11. ARCHITECTURE

Keep business logic outside widgets.

Prefer:

- Riverpod
- repository pattern where useful
- clear models
- services for platform functionality
- reusable widgets

Do not over-engineer.

Do not create layers that contain no useful logic.

Use the simplest architecture that remains maintainable.

---

12. DEPENDENCIES

Before adding a dependency, check whether Flutter or Android already provides the required functionality.

Avoid unnecessary packages.

When adding a package:

- use a maintained package
- use a compatible stable version
- use the minimum necessary dependency

Never add a package just because it is popular.

---

13. ANDROID STORAGE

Use modern Android storage APIs.

Downloaded user-visible files should be stored in appropriate shared/user-accessible locations.

Preferred structure:

Download/
  Hoza Download/
    Videos/
    Audio/

Do not request broad filesystem access unless genuinely required.

Do not store user downloads in a hidden private directory when the purpose is user-accessible downloads.

---

14. SHARE TARGET

The Android application must support receiving shared URLs.

Expected flow:

Other App
   ↓
Share
   ↓
Hoza Download
   ↓
Compact download interface
   ↓
Choose format/quality
   ↓
Download

Do not force unnecessary navigation.

Keep the share experience extremely fast.

---

15. DOWNLOAD RULES

Downloads must have real states:

queued
downloading
paused
completed
failed
cancelled

Support where technically possible:

- progress
- speed
- ETA
- pause
- resume
- cancel
- retry
- duplicate handling

Never allow unlimited simultaneous downloads.

Default maximum:

2

---

16. SAFETY / PLATFORM RESTRICTIONS

The application may download only content that the user is authorized to download or that the source permits.

Never implement:

- DRM circumvention
- authentication bypass
- paywall bypass
- private-content extraction
- security bypass
- rate-limit bypass

If a source is unsupported:

Show a clear error.

Do not invent a workaround.

---

17. SECURITY

Treat URLs, filenames, metadata, and network responses as untrusted.

Prevent:

- path traversal
- malicious filenames
- unsafe file paths
- crashes caused by malformed input

Never log:

- passwords
- tokens
- private credentials
- sensitive user data

---

18. ERROR HANDLING

Never allow expected errors to crash the app.

Handle:

- invalid URL
- unsupported URL
- network failure
- timeout
- insufficient storage
- cancelled download
- server failure
- corrupted response
- duplicate file

Every loading state needs an exit:

Success
OR
Error
OR
Retry

Never leave infinite loading.

---

19. CODE STYLE

Follow Flutter/Dart conventions.

Use:

dart format .
flutter analyze

Prefer readable code over clever code.

Avoid extremely long widgets.

Extract reusable widgets when they improve readability.

Use meaningful names.

Do not add comments explaining obvious Dart code.

Comments should explain WHY, not WHAT.

---

20. BEFORE CHANGING CODE

For every meaningful task:

Step 1

Inspect only the relevant files.

Step 2

Identify the smallest change required.

Step 3

Implement it.

Step 4

Format.

Step 5

Analyze.

Step 6

Run focused tests if appropriate.

Step 7

Continue.

Do not perform unnecessary repository-wide operations.

---

21. DO NOT STOP AFTER ANALYSIS

If the code has a clear fix:

FIX IT.

Do not merely report:

There is an error.

Instead:

1. Identify it.
2. Fix it.
3. Verify it.

Only stop when blocked by something genuinely requiring the user.

---

22. DO NOT ASK UNNECESSARY QUESTIONS

If a reasonable implementation decision can be made from the project requirements:

MAKE THE DECISION.

Do not ask the user about tiny details such as:

- padding
- icon size
- variable names
- widget names
- file names
- animation duration

Use good engineering judgment.

Ask only when the decision materially changes the product.

---

23. PRESERVE WORK

Never delete working functionality just to make the code easier.

Before major refactoring:

Understand dependencies.

After refactoring:

Verify affected functionality.

Do not make unrelated changes.

---

24. GIT

Make changes in small logical units.

Do not modify unrelated files.

Before a large change, inspect:

git status

Never delete user work.

Never reset or revert user changes unless explicitly requested.

Never use destructive Git commands casually.

---

25. COMMAND RULE

Prefer the smallest useful command.

Good:

flutter analyze

Better than repeatedly running:

flutter clean
flutter pub get
flutter analyze
flutter test
flutter build

unless those commands are actually necessary.

Do not run expensive commands without a reason.

---

26. BUILD RULE

During normal development:

Use debug builds.

Do not repeatedly create release APKs after every change.

Only run:

flutter build apk --release

when:

- a major section is complete
- release behavior needs verification
- the user explicitly requests a release build

---

27. PERFORMANCE

Always consider performance.

Avoid:

- unnecessary rebuilds
- large synchronous operations
- blocking the UI thread
- loading huge files into memory
- unnecessary network requests
- unnecessary database queries

Downloads and heavy operations must not freeze the UI.

---

28. FINAL RESPONSE AFTER EACH TASK

Keep the response short.

Use this format:

Completed:
- ...
- ...
- ...

Verified:
- flutter analyze
- relevant tests

Issues:
- None

If something is blocked:

Blocked:
- <short reason>

Next required action:
- <what is needed>

Do not write a long explanation unless requested.

---

MOST IMPORTANT RULE

BUILD THE REAL APP.

Do not optimize for:

- maximum code
- maximum tests
- maximum abstractions
- maximum files
- maximum explanation

Optimize for:

working software with clean code and minimal wasted tokens.

When uncertain, choose the simplest production-quality solution.