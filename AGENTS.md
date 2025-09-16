# Repository Guidelines

## Project Structure & Module Organization
- `app/`: Rails code — `controllers/`, `models/`, `services/`, `jobs/`, `views/`.
- `spec/`: RSpec tests — `models/`, `requests/`, `services/`, `jobs/`, `factories/`, `support/`.
- `config/`, `db/`: app configuration and migrations; seed and migrate here.
- `bin/`: helper scripts (`rails`, `rake`, `rubocop`, `setup`, `brakeman`, `kamal`).
- `lib/`: shared utilities; prefer `app/services` for domain logic.

## Build, Test, and Development Commands
- Setup: `bin/setup` — install gems, prepare DB.
- Run server: `bin/rails s` — starts API on `localhost:3000`.
- Migrate: `bin/rails db:create db:migrate` (add `RAILS_ENV=test` for test DB).
- Test: `bundle exec rspec` or `bin/rails spec` — run entire suite.
- Lint: `bin/rubocop` — uses `rubocop-rails-omakase` rules.
- Security: `bin/brakeman` — static security scan for Rails.

## Coding Style & Naming Conventions
- Ruby `3.4.2`. Follow RuboCop Omakase; fix offenses or add minimal, scoped disables.
- Indentation: 2 spaces; methods/classes in snake_case/CamelCase; constants in SCREAMING_SNAKE_CASE.
- Files: one class/module per file; service objects in `app/services` named `Something::DoThing`.

## Testing Guidelines
- Framework: RSpec with `rails_helper`. Place tests under matching paths (e.g., `app/models/user.rb` → `spec/models/user_spec.rb`).
- Naming: `*_spec.rb`, describe public behavior; use factories from `spec/factories`.
- Running subsets: `bundle exec rspec spec/models` or `rspec spec/requests/whatsapp_spec.rb`.
- Aim for meaningful coverage on models, services, and request flows (WhatsApp ingestion path).

## Commit & Pull Request Guidelines
- Commits: imperative mood; small, focused changes. Prefer prefixes like `feat:`, `fix:`, `chore:`, `test:` (as seen in history).
- PRs: clear summary, linked issue, screenshots/log samples for API responses if relevant, migration notes, and test plan (`rspec` output snippet).
- Require: green CI, passing RuboCop and Brakeman, and added/updated specs for new behavior.

## Security & Configuration Tips
- Never commit secrets. Use `.env` for local env vars; production uses credentials/secure env.
- Validate external payloads; avoid logging PII. Run `bin/brakeman` before merging.
- Deployment uses Kamal (`.kamal/`); coordinate infra changes in the PR.

