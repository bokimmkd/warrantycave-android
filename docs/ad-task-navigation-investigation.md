# Ad-click task navigation candidate

Base: WarrantyCave1.0.40(51), fdb407c1078005c1d16bbc7e3ae642a992f01356.
Owner requested comparison with OTS and PTS and a fix attempt, following the
reported extra black Recents card on both banner formats.

Compared source:
- OTS Android0.5.6(35), c5aaa8675a539874cc5695f106c771de2fd99fb8:
  default activity affinity, singleTop, Activity-backed native AdView.
- PTS production0.2.17(27),139ce76e651e3a9a1167cce705c574e617c77236:
  default activity affinity, singleTop, Activity-backed native AdView.
- WarrantyCave: singleTop but empty MainActivity affinity. SDK AdActivity has
  the package default affinity. Plugin5.1.0 already uses Activity context when
  attached, so replacing banner widgets is not justified by this comparison.

Small runtime change: use a version-qualified task-affinity string. Android11+
uses com.warrantycave.app, matching SDK activities and both working references.
Android10 and earlier keep empty affinity. Minimum OS support remains unchanged.
The older-OS ad navigation limitation is intentionally not claimed fixed.
No launch-mode change, hidden Recents activity, forced finish, ad-ID change,
plugin/SDK upgrade, billing/consent/storage/backend change or UI redesign.

Why the OS split: Android documents that API30+ includes OS patches for the
StrandHogg task-affinity vulnerability; keep the existing partial mitigation
below that boundary rather than removing it globally.
https://developer.android.com/privacy-and-security/risks/strandhogg
https://developer.android.com/guide/components/activities/tasks-and-back-stack
https://github.com/googleads/googleads-mobile-flutter/issues/1330
https://github.com/googleads/googleads-mobile-flutter/issues/1322
https://github.com/flutter/flutter/issues/63559

Validation uses actual Android task routing, not a manifest text-only test.
A debug-only same-package probe models an SDK NEW_TASK bridge. A second
installed test package models an offline destination; actual Back presses
return through the bridge to the original MainActivity. A counterfactual empty
root must still reproduce two app tasks on the same OS. Launcher reentry must
reuse the original task. Effective PackageManager metadata also checks the
legacy security boundary and the actual SDK AdActivity affinity.

The fixtures are debug/androidTest only and absent from release builds.
The new CI builds diagnostic APKs only, no AAB, version bump or Play submission.
Existing Flutter/backend/native unit suites also run. Instrumentation runs on
API29 and35; API29 checks legacy protection and counterfactual only, with two
modern-OS navigation tests intentionally inapplicable.

Limits: this reproduces Android task routing with local fixtures, not actual
Google SDK ad click behavior on the owner's Samsung. Final acceptance still
requires both banner sizes using TEST ads, destination Back, Recents selection,
repeat/background/resume, shortcuts/notifications/PDF/share and launcher checks.
Do not call this a confirmed physical-device fix before those checks.
