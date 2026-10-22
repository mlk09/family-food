# Architecture

## 1. Folder structure

```
lib/
├── main.dart                 bootstrap: prefs, Supabase (if configured), notifications
├── app.dart                  MaterialApp.router, themes, text-scale clamp
├── core/
│   ├── config/env.dart       --dart-define values (public only)
│   ├── constants/            categories, units, diets, roles, warnings
│   ├── theme/                AppTheme (light/dark), AppColors, AppPalette extension
│   ├── services/             AIService · OfflineChef · AuthService · NotificationService
│   └── utils/                IngredientMatcher · Validators · Safety · AppFailure · ids · emoji
├── models/                   pure data classes with tolerant fromJson/toJson
├── data/
│   ├── session.dart          SessionMode (signedOut / demo / cloud), Supabase client providers
│   ├── local_store.dart      per-account JSON cache
│   ├── sync_engine.dart      ordered outbox → Supabase
│   ├── providers.dart        offline-first repositories (Riverpod AsyncNotifiers)
│   ├── settings.dart         theme + notification prefs
│   ├── recipe_library.dart   27 built-in recipes (instant + offline)
│   └── demo_data.dart        Demo Mode seed
├── features/<feature>/       screens + controllers (business logic outside widgets)
├── widgets/                  shared UI
└── routes/                   go_router config + bottom-navigation shell
```

## 2. Database schema (Supabase Postgres)

```
auth.users ─┬─< profiles (1:1)            ─┐
            ├─< user_preferences (1:1)     │ private
            ├─< ai_conversations ─< ai_messages
            │
            ├─< family_members >─ families  (one family per user, invite_code)
            │
            └─< ingredients ───────────────┐
               recipes ─< saved_recipes     │ user_id + family_id
               meal_plans ─< meal_plan_items│ (shared with family via RLS)
               shopping_lists ─< shopping_list_items
ingredient_categories (reference)     ai_usage (server-only rate limit)
```

Every user table has `user_id` (and `family_id` where data is shareable), UUID PKs and `created_at`/`updated_at`. See `supabase/schema.sql`.

## 3. Navigation

```
/splash → /onboarding → /login ⇄ /signup ⇄ /forgot
                            │ (auth or Demo Mode)
                            ▼
        ┌───────────── Shell (bottom nav + 🤖 FAB) ─────────────┐
        │ /home   /kitchen   /plan   /shopping   /profile        │
        └────────────────────────────────────────────────────────┘
  push: /cook (What Can I Cook?) → /recipe → /cooking
        /kitchen/add (add / edit / scan)   /chef (Chef AI, optional recipe)
        /family   /saved
```

The router redirects on session changes: signed out users go to auth, and signed-in users are kept away from auth pages.

## 4. AI architecture

```
┌─────────────── Flutter ───────────────┐
│ UI → Controller (Riverpod)            │
│   ├─ IngredientMatcher  (0 ms, local) ─┼─▶ instant results
│   └─ AIService ──HTTPS──────────────────┼──▶ Supabase Edge Function "chef-ai"
│        ▲  validate (Recipe.tryParseAi) │      ├─ verify JWT (or Demo key if allowed)
│        │  fallback → OfflineChef       │      ├─ rate limit (ai_usage RPC)
└────────┼───────────────────────────────┘      ├─ bounded, sanitised context → system prompt
         │                                       ├─ OpenAI: strict JSON schema / SSE stream / vision
         └──────── validated JSON or text ◀──────┴─ sanitise → respond
```

- The OpenAI key and the service-role key exist only as Edge Function secrets.
- Context (kitchen, diet, allergies, favourites, plan, family size) is sent with the request, so there are no extra DB round-trips and latency stays low.
- Chat streams token by token. Structured actions use strict JSON schemas and are re-validated in the app.
- Every AI feature has an on-device fallback, so the app never dead-ends.

## 5. Offline-first data flow

```
Widget ─watch─▶ Repository (AsyncNotifier)
                 ├─ build(): return LocalStore cache immediately
                 ├─ refresh(): Supabase select (RLS-filtered) → cache → state
                 └─ write(): update state + cache → SyncEngine.enqueue(op)
SyncEngine: ordered outbox in LocalStore; flush on enqueue, app start and reconnect;
            network errors keep ops queued, server rejections drop the op.
```

## 6. Deployment and QR

```
                      ┌──────────────── GitHub Actions (on tag vX.Y.Z) ───────────────┐
 Flutter project ─────┤ test → APK → GitHub Release asset (stable URL)                │
                      │      → web build (/app/) + landing page → GitHub Pages         │
                      └───────────────────────────────────────────────────────────────┘
 iOS: Xcode → flutter build ipa → App Store Connect → TestFlight link → config.js
                                      │
              https://<host>/  (download landing page, device detection)
                                      ▲
              tools/make_qr.py <that URL> → family_food_assistant_qr.png + qr_print.html
```
