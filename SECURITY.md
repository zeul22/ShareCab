# Security Policy

Do not report security vulnerabilities in public issues, pull requests, or
discussions.

Enable GitHub private vulnerability reporting when the repository becomes public
if the hosting plan supports it.

Security contact: anandrahul044@gmail.com

## Supported Scope

Security reports are in scope when they affect:

- Authentication, OTP, session handling, or account takeover.
- Payment, subscription, or unlock flows.
- Rider or driver personal data.
- Driver eligibility, dispatch, trip lifecycle, or safety-critical state.
- Backend API authorization.
- Secret exposure in source, logs, builds, or documentation.
- Mobile app behavior that can compromise users, drivers, trips, or payments.

## Out of Scope

The following are usually out of scope unless they demonstrate a concrete,
exploitable risk:

- Denial-of-service tests against live services.
- Automated scanner output without validation.
- Missing headers on static documentation pages.
- Social engineering or physical attacks.
- Reports that require access to secrets, private accounts, or data you do not
  have permission to use.
- Issues in third-party services that ShareCab cannot fix directly.

## Reporting Requirements

Include:

- A clear summary.
- Affected component, endpoint, screen, or package.
- Steps to reproduce.
- Impact and likely severity.
- Proof of concept, if safe to share privately.
- Whether any real data, credentials, or accounts were accessed.

## Safe Harbor

Good-faith security research is welcome when it avoids privacy violations,
service disruption, extortion, persistence, data destruction, and public
disclosure before maintainers can respond.

## Response Target

Maintainers aim to acknowledge valid reports within 3 business days and provide
a remediation plan or status update within 14 days. Critical issues may be
handled faster and may require temporary private coordination.
