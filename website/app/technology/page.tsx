import Link from 'next/link';
import { Section } from '@/components/Section';
import { FeatureCard } from '@/components/FeatureCard';

export const metadata = {
  title: 'Technology — ShareCab',
  description:
    'How ShareCab is built: Flutter rider and driver apps, Node.js backend, MongoDB, MSG91 OTP, Razorpay, AdMob, Google Maps, and source-available public demo boundaries.',
};

const stack = [
  ['Rider app', 'Flutter, Provider, Google Maps, Places, AdMob rewarded ads, Razorpay checkout, MSG91 OTP widget.'],
  ['Driver app', 'Flutter, foreground location, dispatch offers, pickup sequencing, OTP verification, subscription state.'],
  ['Backend', 'Node.js, Express, Mongoose, MongoDB, Socket.IO, JWT auth, matching, fare calculation, trip lifecycle.'],
  ['Website', 'Next.js App Router, Tailwind, static marketing and documentation entry points.'],
] as const;

const publicScope = [
  ['Public-functional', 'Rider trip planning, matching, pricing, ad-watch unlocks, payment test/stub flows, and backend state transitions.'],
  ['Public-limited', 'Driver app source, onboarding UI, subscription screens, dispatch UI, and local/demo driver flows.'],
  ['Private/gated', 'Real driver fleet operations, production dispatch controls, KYC providers, fraud rules, safety playbooks, and live credentials.'],
] as const;

const providers = [
  ['OTP', 'MSG91 Flutter widget in production, dev OTP fallback for local work, backend token verification before issuing ShareCab JWTs.'],
  ['Payments', 'Razorpay orders, signature verification, webhook confirmation, and stub mode when keys are absent.'],
  ['Ads', 'AdMob rewarded ads for the free unlock path, with official test ad units for public/demo builds.'],
  ['Maps', 'Google Maps, Places, Geocoding, Directions, and haversine fallback when server-side directions are unavailable.'],
] as const;

export default function TechnologyPage() {
  return (
    <>
      <section className="container-page pt-20 pb-10">
        <div className="inline-flex items-center gap-2 rounded-full border border-brand-200 bg-brand-50 px-3 py-1 text-xs font-medium text-brand-700">
          Source-available architecture
        </div>
        <h1 className="mt-5 h-display max-w-4xl">
          A real mobility stack, documented for public review.
        </h1>
        <p className="mt-6 text-lg muted max-w-3xl">
          ShareCab is being prepared as a source-available project under PolyForm Shield.
          The public repo is designed to show meaningful rider-side flows and backend
          mechanics while keeping production driver operations, credentials, KYC,
          fraud controls, and safety operations private.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link href="/how-it-works" className="btn-primary">See product flow</Link>
          <Link href="/contact" className="btn-secondary">Ask about the project</Link>
        </div>
      </section>

      <Section eyebrow="System stack" title="Four parts, one product loop.">
        <div className="grid sm:grid-cols-2 gap-5">
          {stack.map(([title, text]) => (
            <InfoCard key={title} title={title}>{text}</InfoCard>
          ))}
        </div>
      </Section>

      <Section
        alt
        eyebrow="Public release boundary"
        title="Useful in public. Safe for production."
        intro="The public project should be inspectable and runnable without becoming a turnkey clone of the official ShareCab service."
      >
        <div className="grid lg:grid-cols-3 gap-5">
          {publicScope.map(([title, text]) => (
            <InfoCard key={title} title={title}>{text}</InfoCard>
          ))}
        </div>
      </Section>

      <Section eyebrow="Core mechanics" title="The rider-side funnel stays functional.">
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          <FeatureCard
            icon="1"
            title="Phone OTP auth"
            description="The app uses MSG91 widget verification in production and a clearly gated dev fallback for local work."
          />
          <FeatureCard
            icon="2"
            title="Destination matching"
            description="The backend matches riders by pickup proximity, destination proximity, detour budget, cab capacity, and luggage rules."
          />
          <FeatureCard
            icon="3"
            title="Unlock gate"
            description="Serious matches unlock through rewarded ads or a Razorpay payment path, with public demo stubs preserving the same state transitions."
          />
          <FeatureCard
            icon="4"
            title="Fare calculation"
            description="Pricing is calculated in paise with vehicle classes, distance bands, booking fee, optional GST, surge windows, and shared-fare allocation."
          />
          <FeatureCard
            icon="5"
            title="Realtime state"
            description="Socket.IO and REST endpoints coordinate chat, match state, trip state, dispatch offers, and driver location updates."
          />
          <FeatureCard
            icon="6"
            title="India-first locale"
            description="The apps resolve supported Indian languages instead of assuming English-only usage, including localized platform UI and place results."
          />
        </div>
      </Section>

      <Section
        alt
        eyebrow="Provider model"
        title="Production providers are isolated behind safe defaults."
      >
        <div className="grid sm:grid-cols-2 gap-5">
          {providers.map(([title, text]) => (
            <InfoCard key={title} title={title}>{text}</InfoCard>
          ))}
        </div>
        <p className="mt-6 text-sm muted max-w-3xl">
          No production API keys, signing assets, real rider data, KYC payloads, or
          provider secrets should live in the public repository. Developers bring
          their own restricted keys or use the documented stub/test paths.
        </p>
      </Section>

      <Section
        eyebrow="License"
        title="Source-available under PolyForm Shield."
        intro="ShareCab is not MIT-licensed and not OSI-approved open source. The code is available for transparency, learning, review, and non-competing collaboration while competing mobility marketplace use requires separate permission."
      >
        <div className="grid sm:grid-cols-3 gap-5">
          <InfoCard title="Allowed direction">
            Study, review, local demo work, documentation, tests, accessibility,
            localization, and non-competing improvements.
          </InfoCard>
          <InfoCard title="Protected business">
            Cab-sharing, ride-sharing, rider matching, driver dispatch, driver
            onboarding, shared mobility marketplaces, and related services.
          </InfoCard>
          <InfoCard title="Public demo">
            Rider-side flows remain demonstrable; real production driver operations
            are explicitly gated.
          </InfoCard>
        </div>
      </Section>
    </>
  );
}

function InfoCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl bg-white border border-ink-300/40 p-6">
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-sm muted leading-relaxed">{children}</p>
    </div>
  );
}
