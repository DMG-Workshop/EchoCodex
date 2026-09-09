# Echo Codex: Product Ideas

A deliberately broad backlog for turning Echo Codex from a private recorder into a dependable personal knowledge and action system. Ideas are grouped by product surface, not priority.

Original idea numbers are retained so references stay stable as completed ideas are removed.

## Capture and recording
0. Improve cell layouts and tablet support on Android and Apple.
1. Add one-tap recording from the home screen.
2. Add a lock-screen recording control.
3. Add a home-screen widget with record and pause actions.

## Transcription and audio intelligence

12. Let users correct transcript words while listening to the audio. Done: playback bar with tap-to-edit segments in the transcript tab.
13. Highlight the currently spoken transcript segment during playback. Done: same playback bar highlights the active segment as it plays.
15. Let users choose transcription language per recording. Done: per-recording language override, set from the processing queue and applied on retry.
18. Offer a glossary that learns preferred spellings locally.
19. Add transcript confidence highlighting.
20. Let users choose between speed, accuracy, and battery profiles.

## Summaries and structured notes

21. Add summary presets for meetings, lectures, interviews, calls, and brainstorming. Done: five built-in presets seeded as selectable note templates.
23. Generate a short executive brief alongside the full note.
24. Extract decisions separately from action items.
25. Extract open questions and unresolved risks.
26. Detect commitments and identify who made them.
27. Add a "what changed" summary when a note is regenerated.
28. Generate a glossary of unfamiliar terms from each recording.
29. Add quote extraction with links back to transcript timestamps.
30. Let users ask follow-up questions against one recording.

## Editing and knowledge organization

31. Add a rich text editor for generated notes.
32. Preserve the source transcript beside every generated section.
33. Support backlinks between related recordings and notes.
34. Add tags with autocomplete and tag management.
35. Add folders and nested collections.
36. Support pinned notes and favorite recordings.
39. Let users merge two recordings into one note.
40. Let users split a long recording into chapters.

## Tasks and planning

42. Let users assign tasks to contacts or local people records.
43. Add recurring tasks generated from recurring meetings.
44. Add task priorities and custom status values.
45. Support dependencies between tasks.
48. Show overdue actions with their source transcript evidence.
49. Add effort estimates and time-blocking for tasks.
50. Export a project plan with tasks, owners, dates, and dependencies.

## Boards, timelines, and views

52. Add swimlanes by owner, project, or priority.
57. Add a dashboard of recent recordings, open actions, and decisions.
58. Add a mind-map view for concepts extracted from a note.
59. Add a conversation map showing speakers and topic shifts.
60. Let users export any view as an image or PDF.

## Import, export, and integrations

62. Add drag-and-drop import on desktop platforms. Done: drop audio or video onto the record screen.
64. Add a Watch a folder and automatically import new recordings. Done: choose a watch folder in Workflow features.
68. Add a direct export to Notion databases. Done: webhook and Notion export from the note export sheet.

## Privacy and local-first controls


## Collaboration and sharing

81. Share a timestamped transcript excerpt without sharing the full recording.
82. Create a read-only share package with an expiration date.
83. Add comments anchored to note sections and transcript timestamps.
84. Let collaborators suggest edits without changing the source note.
85. Add approval status for finalized notes.
88. Support importing comments and decisions from shared note packages.
89. Add conflict-aware merging for edited notes.
90. Show provenance for every generated sentence and extracted task.

## Reliability, accessibility, and polish

95. Support VoiceOver, TalkBack, dynamic type, and high-contrast themes.

## Desktop platforms

103. Add an AppImage release for portable Linux installs. Done: `packaging/appimage/build-appimage.sh`.
104. Add an Arch Linux PKGBUILD and AUR release path. Done: `packaging/arch/PKGBUILD`.
106. Add Linux desktop notifications and system-tray controls. Done: tray record/show/quit plus Linux notification details.

## Integrations

108. Expand the Foundry VTT module beyond Journal import. Done: a file-picker import dialog plus per-task/decision/question document creation in `integrations/foundry_vtt`.

## Suggested first slice

Next priorities: expand Foundry VTT beyond Journal import, add transcript word correction while listening, highlight the currently spoken segment during playback, add per-recording language choice, and add summary presets for meetings, lectures, interviews, calls, and brainstorming. These continue improving the core loop without requiring a hosted backend.
