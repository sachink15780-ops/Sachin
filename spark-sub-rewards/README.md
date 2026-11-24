# Spark Sub Rewards (GitHub branch: spark-sub-rewards)

Mobile-first frontend and Supabase backend starter.

## 1. Create Supabase project
Create a project at https://supabase.com/dashboard and wait for it to finish provisioning.

## 2. Create tables
In Supabase Dashboard → SQL Editor, open and run `supabase/schema.sql`.

## 3. Configure browser client
Open `spark-sub-rewards/supabase-config.js` and paste your project URL and **publishable/anon key** from Supabase Project Settings → API. Never paste service_role/secret keys into frontend.

## 4. Storage bucket
Create a Storage bucket called `task-proofs`, set it private. Create storage policies allowing authenticated users to upload only into their own user-id folder, and admins to read proof files. Do not make proof screenshots public.

## 5. Admin
Do not promote admins from the browser. Set a user's role to admin from Supabase SQL Editor only, after identifying that user's UUID:
```sql
update public.profiles set role='admin' where id='USER_UUID';
``

## Notes
- The frontend prototype currently includes demo data. Supabase integration files are provided separately and require project URL/key before connecting.
- No payment gateway or payout automation is included. Withdrawals should be reviewed manually.
- YouTube subscription state cannot be securely verified through pasted links; proof review is manual.
- Avoid collecting Aadhaar/PAN or other sensitive identity documents until a lawful, secure KYC process is designed.
