# Source Availability and Public Repository Boundaries

ShareCab is public-source/source-available, not OSI-approved open source.

The distinction matters: ShareCab allows public reading, study, and
non-competing collaboration, but reserves competing cab-sharing, ride-sharing,
driver-dispatch, and production mobility marketplace use for the official
ShareCab maintainers unless a separate written commercial license is granted.

## License Model

- Repository source: PolyForm Shield License 1.0.0 via
  [LICENSE.md](../LICENSE.md).
- Contributions: governed by [CONTRIBUTING.md](../CONTRIBUTING.md) and
  [CONTRIBUTOR_LICENSE_TERMS.md](../CONTRIBUTOR_LICENSE_TERMS.md).
- Brand assets: governed by [TRADEMARKS.md](../TRADEMARKS.md).
- Dependencies: remain under their own third-party licenses.

## Public in This Repository

The public repository may include:

- Rider app source.
- Driver app source, with production driver operations disabled unless private
  production configuration is present.
- Backend API source.
- Website source.
- Local development tooling.
- Documentation.
- Tests.
- Example environment files.
- Non-secret configuration.

## Public Functional Scope

The public repository should support a useful demo/dev path:

- Rider trip planning.
- Matching and fare calculation.
- Ad-watch unlock through test ad units or a stub provider.
- Rider payment unlock through Razorpay test mode or a stub provider.
- Backend state transitions for auth, matching, unlocks, and trips.
- Simulated or seeded drivers for rider-flow demos.

The public repository should not require the real driver app, real drivers, or
production provider credentials to demonstrate the rider-side flow.

See [PUBLIC_RELEASE_PLAN.md](./PUBLIC_RELEASE_PLAN.md) for the operational
release plan.

## Not Public

The public repository must not include:

- Production `.env` files.
- API keys, auth tokens, signing keys, service account files, certificates, or
  keystores.
- App Store Connect, Play Console, Firebase, AWS, MongoDB, Razorpay, MSG91,
  Google Maps, or KYC provider credentials.
- Fraud heuristics that would materially weaken platform safety if public.
- Private safety operations playbooks.
- Real user, rider, driver, trip, payment, or KYC data.
- Private commercial agreements.
- Real driver fleet operations, production driver availability, and production
  dispatch controls.

## Adding New Modules

Before adding a module, ask:

- Can contributors run it locally without production secrets?
- Does it expose fraud, safety, payment, or identity-verification internals?
- Does it contain regulated, private, or user-identifying data?
- Would publishing it let a third party impersonate ShareCab or operate the
  official service?

If the answer creates real risk, keep the module private and document only the
public interface.

## Public Issue Boundaries

Use public issues for reproducible bugs, docs, feature proposals, and local
development problems.

Use private security reporting for vulnerabilities. Do not include secrets,
production logs, private user data, or exploit details in public issues.
