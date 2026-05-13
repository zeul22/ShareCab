# Contributing to ShareCab

ShareCab welcomes issues, documentation improvements, bug fixes, and focused
feature proposals that improve the source-available project.

Before contributing, read:

- [LICENSE.md](./LICENSE.md)
- [CONTRIBUTOR_LICENSE_TERMS.md](./CONTRIBUTOR_LICENSE_TERMS.md)
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)
- [SECURITY.md](./SECURITY.md)

## Licensing of Contributions

By opening a pull request, issue, discussion, patch, or other contribution, you
agree that your contribution is provided under the terms in
[CONTRIBUTOR_LICENSE_TERMS.md](./CONTRIBUTOR_LICENSE_TERMS.md).

This is important because ShareCab is source-available for public review and
non-competing use, while the ShareCab maintainers may also operate official
commercial apps and services.

## What to Work On

Good contributions are usually one of these:

- Clear bug fixes with a reproduction.
- Small UX, accessibility, localization, or documentation improvements.
- Tests around matching, auth, dispatch, payment, safety, or OTP behavior.
- Well-scoped infrastructure improvements that do not require private secrets.

Large features, new providers, payment changes, security-sensitive changes, and
ride-safety changes should start as an issue before a pull request.

## Local Setup

Start with [docs/getting-started.md](./docs/getting-started.md), then run the
service you are changing:

```bash
cd backend && npm install && npm test
cd app && flutter pub get && flutter analyze
cd driver && flutter pub get && flutter analyze
cd website && npm install && npm run lint
```

Run only the commands that apply to your change, but explain what you skipped in
the pull request.

## Pull Request Expectations

- Keep the pull request focused on one problem.
- Include screenshots or screen recordings for visible UI changes.
- Add or update tests when behavior changes.
- Update docs when setup, environment variables, APIs, or user flows change.
- Do not commit secrets, local `.env` files, production credentials, private
  keys, signing files, API tokens, or real user data.
- Do not include generated dependency churn unless the change requires it.
- Mention any migration, rollout, or operational risk.

## Branch and Commit Style

Use short branch names such as `fix-driver-otp`, `docs-security-policy`, or
`feat-locale-routing`.

Commit messages should be specific and imperative, for example:

```text
Add locale-aware places requests
Document source-available contribution terms
Fix driver dispatch timeout handling
```

## Review

Maintainers may request tests, docs, security clarification, or a smaller scope
before merging. Changes that affect production operations, rider safety,
driver eligibility, payments, authentication, or data privacy require stricter
review.
