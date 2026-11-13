# المبنى الحي · Living Building

A platform that turns problems in the College of AI building into student course and
graduation projects, for the "Our Future is Green" competition.

## What is in this folder

| File | What it is |
|---|---|
| `index.html` | The whole platform: one page, Arabic and English, no build step. |
| `api/ai.js` | A small server function that passes AI requests to Groq and keeps the key secret. |
| `config.js` | Turns on sign-in. Empty by default, so the page runs without accounts. |
| `supabase/schema.sql` | The database for sign-in, roles and shared data. |

## Run it on free hosting (Vercel)

1. Create a free account at groq.com and make an API key.
2. Put this folder in a GitHub repository.
3. In Vercel, choose "Add New Project" and import the repository. No settings need changing.
4. In the project's Settings > Environment Variables, add `GROQ_API_KEY` with your key.
5. Deploy. The page is at the address Vercel gives you.

Optional variables: `AI_MODEL` (the model name; check Groq's current list, since names change)
and `AI_URL` (any OpenAI-compatible endpoint, if you switch provider).

Opening `index.html` directly from your disk also works. The AI features then fall back to
basic keyword sorting, and the chat tools say AI is not available.

## Sign-in with university email (roles and shared data)

Without this, the self-hosted page keeps data in each visitor's own browser and treats every
visitor as the dean. With it, people sign in with a one-time link sent to their university
email, everyone sees the same data, and each person gets a role:

| Role | Can do |
|---|---|
| Student | Report problems, add ideas, reserve an idea for themselves, use the advisor, read the dean's plan |
| Supervisor | Everything a student can, plus approve reservations, mark projects done, set the size of the year's plan, and write its letter |
| Dean | Reads the dean's brief, which is always ready, and can endorse the plan with one tap. Nothing is required of the dean. |

Steps (about 20 minutes):

1. Create a free project at supabase.com.
2. Open SQL Editor, paste all of `supabase/schema.sql`, and run it.
3. Still in SQL Editor, set your university's email domain (the part after @):
   `update public.allowed_domains set domain = 'your-university.edu.iq' where domain = 'example.edu.iq';`
   Add more domains with `insert into public.allowed_domains (domain, role) values ('...', 'student');`
4. In Authentication > URL Configuration, set Site URL to your Vercel address, and add it
   under Redirect URLs too.
5. In Project Settings > API, copy the Project URL and the `anon` `public` key into
   `config.js`, and list your domain in `allowedDomains`.
6. In Vercel, add `SUPABASE_URL` and `SUPABASE_ANON_KEY` as environment variables too, so the
   AI function only answers signed-in people. Redeploy.
7. Sign in once yourself, then make yourself the dean in SQL Editor:
   `update public.profiles set role = 'dean' where email = 'you@your-university.edu.iq';`
   Do the same with `'supervisor'` for each supervisor after they have signed in once.

Notes:
- Supabase's built-in email sender is limited to a few emails per hour, which is enough to
  test. For a whole college, connect your own email sender under Authentication > SMTP
  Settings.
- The database itself enforces the rules: only supervisors and the dean can approve, only
  supervisors and the dean can change the plan, and a student can reserve only for themselves and cannot
  take an idea someone else holds.
- **This was tested against a stand-in for Supabase, not a real project.** Test the full
  flow (sign-in link, reserve, approve) once you have set it up.

## Roles on the version published as a Claude page

The page uses the viewer's Claude account: the owner is the dean, people invited as Editors
are supervisors, and everyone else is a student. Students need Contributor access to save
reports and reservations.

## Still to check

- **The AI function has not been run against Groq from this project.** Test it after
  deploying, and try two or three models with Iraqi-dialect questions before choosing one.

## Things to edit before presenting

- `ROOMS` in `index.html`: the floor plan was drawn from a hand sketch. Adjust names, sizes and positions
  to match the real second floor.
- `SEEDS`: the 30 sample ideas. Every impact figure is a rough placeholder, not a
  measurement. Replace them as real numbers arrive.
- `HOLD`: how long a reservation lasts without supervisor approval (21 days).

## Privacy of the advisor chat

Chat messages live only in the page's memory and are gone when the tab closes. They are
sent to the AI provider to get a reply, and `api/ai.js` does not log or store them. Read
your provider's terms before promising students more than "not saved on our servers".
