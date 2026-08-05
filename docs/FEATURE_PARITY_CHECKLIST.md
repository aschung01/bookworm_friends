# Feature Parity Checklist: GetX -> Riverpod Migration

> Track every feature gap to ensure zero unintended regressions before publish.

## Intentional Removals (confirmed)

- [x] Kakao OAuth login — removed, Apple + Google only
- [x] Home page TabBarView swipe navigation — replaced with avatar bar (confirm?)

---

## P0: Blockers (app won't work correctly without these)

- [x] **Deep link handling** — `app_links` wired in `main.dart`, passes URI to `supabase.auth.getSessionFromUrl()`
- [x] **Push notification initialization** — `NotificationService.initialize()` in main, token registered on auth state change
- [x] **EasyLoading feedback on mutations** — all actions wrapped with show/showSuccess/showError
- [x] **Error handling (try/catch)** — all provider actions wrapped, user-facing error toasts
- [x] **Account deletion (회원 탈퇴)** — settings UI + confirmation dialog + `delete-account` Edge Function

---

## P1: Core UX Features (app works but key functionality missing)

- [x] **Date selection when adding books** — date pickers shown for "읽는 중" and "읽음" statuses
- [x] **Drag-and-drop books between shelves** — LongPressDraggable + DragTarget in editLibrary mode
- [x] **Memo editing** — tap memo shows menu (수정/삭제), edit reuses write memo bottom sheet
- [x] **Poke feature (콕 찌르기)** — "콕 찌르기" button in subheader when viewing friend's library + `pokeUser()` RPC
- [x] **Notification tap handling** — `onDidReceiveNotificationResponse` + `onMessageOpenedApp` navigate on tap
- [x] **Friend library finished books section** — friend view now shows finished books via `userFinishedBooksProvider`
- [x] **Unfollow confirmation dialog** — "정말 팔로우를 취소하시겠어요?" dialog before unfollowing

---

## P2: Secondary UX Features (polish, not blockers)

- [x] **Followers/following list bottom sheet** — settings shows counts, tap opens tabbed list
  - Files: `lib/ui/pages/settings_page.dart` (_FollowListSheet)

- [x] **Following user info dialog** — long-press friend avatar shows dialog with stats, poke, unfollow
  - Files: `lib/ui/pages/home_page.dart` (_showFriendInfoDialog)

- [x] **In-app review** — "간단하게 리뷰 남기기" row in settings calls `InAppReview.instance.openStoreListing()`
  - Files: `lib/ui/pages/settings_page.dart`

- [x] **App version display** — shows version via `package_info_plus` in settings
  - Files: `pubspec.yaml`, `lib/ui/pages/settings_page.dart`

- [x] **Book deletion in edit mode** — X badge overlay on books in edit mode; tap to confirm delete
  - Files: `lib/ui/pages/home_page.dart` (_ShelfRow)

- [x] **Search pagination** — loads more results on scroll to bottom via AutoDisposeAsyncNotifier
  - Files: `lib/ui/pages/search_book_page.dart`

---

## P3: Polish & Micro-interactions (nice-to-have)

- [x] **Loading shimmer effects** — shimmer placeholders matching shelf/book layout
  - Files: `lib/ui/widgets/loading_blocks.dart`

- [x] **Pull-to-refresh** — `RefreshIndicator` wrapping library, invalidates providers on pull
  - Files: `lib/ui/pages/home_page.dart`

- [x] **Book press shadow animation** — elevation/translate animation on tap-down/tap-up
  - Files: `lib/ui/widgets/book_widget.dart`

---

## Dead Code to Clean Up

- [x] `lib/ui/pages/book_info_tab_page.dart` — deleted (stub, never used)
- [x] `lib/ui/pages/book_memo_tab_page.dart` — deleted (stub, never used)
- [x] `go_router` in pubspec.yaml — removed (unused)
- [x] `flutter_shake_animated` in pubspec — removed (unused)

---

## Progress

| Priority | Total | Done | Remaining |
|----------|-------|------|-----------|
| P0       | 5     | 5    | 0         |
| P1       | 7     | 7    | 0         |
| P2       | 6     | 6    | 0         |
| P3       | 3     | 3    | 0         |
| Cleanup  | 4     | 4    | 0         |
