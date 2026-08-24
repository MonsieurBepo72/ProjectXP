# Project XP — Push notifications backup

## Edge Function
Name:
send-private-message-notification

Local path:
supabase/functions/send-private-message-notification/index.ts

## Required Supabase Edge Function secret
FIREBASE_SERVICE_ACCOUNT_JSON

Important:
- Store the Firebase service-account JSON only in Supabase Secrets.
- Never commit the private service-account JSON to Git/GitHub.
- The client-side google-services.json and lib/firebase_options.dart are separate Firebase client configuration files.

## Database webhook
Name:
private-message-push

Configuration:
- Table: public.private_messages
- Event: INSERT only
- Destination: Supabase Edge Function
- Function: send-private-message-notification
- Method: POST
- Header: apikey = Supabase server secret key
- Content-Type: application/json
- Verify JWT with legacy secret: OFF for this Edge Function

## Push token table
Table:
public.push_device_tokens

Purpose:
Stores FCM device tokens associated with the current Supabase auth user.

Expected columns:
- id uuid primary key
- user_id uuid -> auth.users(id)
- token text unique
- platform text
- created_at timestamptz
- updated_at timestamptz

RLS:
Users may select/insert/update/delete only their own rows.

## Tested
The end-to-end path was validated on:
- tel1 / OnePlus
- tel2 / Galaxy

Flow:
private message INSERT
-> Database Webhook
-> Edge Function
-> Firebase Cloud Messaging
-> Android notification
