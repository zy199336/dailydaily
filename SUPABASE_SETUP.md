# Supabase Setup

This app only uses one dedicated table:

```text
public.daily_schedule_tasks
```

It does not require or modify tables from other projects.

## Steps

1. Open the Supabase project:

   ```text
   https://kawhxjhiqqjjinbxcoqm.supabase.co
   ```

2. Go to SQL Editor.

3. Paste and run the full contents of:

   ```text
   supabase_daily_schedule.sql
   ```

4. Return to this workspace and verify:

   ```powershell
   dart run tool/check_supabase.dart
   ```

Expected success output:

```text
OK: Supabase table "daily_schedule_tasks" is reachable.
```

## Safety Scope

The SQL script:

- Creates `public.daily_schedule_tasks` if it does not exist.
- Creates indexes only for `daily_schedule_tasks`.
- Enables row level security only for `daily_schedule_tasks`.
- Adds select/insert/update policies only for `daily_schedule_tasks`.
- Does not contain `drop`, `truncate`, or `delete from`.

