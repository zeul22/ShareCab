import Link from 'next/link';
import { Section } from '@/components/Section';
import { FeatureCard } from '@/components/FeatureCard';
import { AppStoreButtons } from '@/components/AppStoreButtons';

export default function HomePage() {
  return (
    <>
      {/* Hero */}
      <section className="relative">
        <div className="container-page pt-20 pb-16 sm:pt-28 sm:pb-24 grid lg:grid-cols-2 gap-12 items-center">
          <div>
            <div className="inline-flex items-center gap-2 rounded-full border border-brand-200 bg-brand-50 px-3 py-1 text-xs font-medium text-brand-700">
              Source-available cab sharing for India
            </div>
            <h1 className="mt-5 h-display">
              Share the cab.<br />
              <span className="text-brand-600">Split the fare.</span>
            </h1>
            <p className="mt-6 text-lg muted max-w-xl">
              ShareCab matches riders heading the same way, unlocks serious matches
              through ads or payment, and coordinates the trip with OTP, chat, fare
              sharing, and realtime state.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Link href="/how-it-works" className="btn-primary">See how it works</Link>
              <Link href="/technology" className="btn-secondary">Explore the stack</Link>
            </div>
            <div className="mt-10 flex items-center gap-6 text-sm muted">
              <div><span className="font-semibold text-ink-900">2–4 km</span> matching radius</div>
              <div><span className="font-semibold text-ink-900">Ads/pay</span> unlocks</div>
              <div><span className="font-semibold text-ink-900">Shield</span> licensed</div>
            </div>
          </div>

          <div className="relative">
            <div className="aspect-[4/5] rounded-3xl bg-gradient-to-br from-brand-100 via-white to-brand-50 border border-brand-200/60 p-6 shadow-xl">
              <div className="rounded-2xl bg-white p-5 shadow-sm">
                <div className="text-xs font-semibold uppercase tracking-wider text-brand-700">Live match</div>
                <div className="mt-3 space-y-3">
                  <Row dot label="You" sub="Connaught Place" />
                  <Row dot label="Co-rider" sub="Within 1.2 km of your drop" />
                </div>
              </div>
              <div className="mt-5 rounded-2xl bg-white p-5 shadow-sm flex items-center justify-between">
                <div>
                  <div className="text-xs muted">Solo fare</div>
                  <div className="text-lg font-semibold line-through opacity-60">₹128</div>
                </div>
                <div className="text-right">
                  <div className="text-xs text-brand-700 font-semibold">Shared fare</div>
                  <div className="text-2xl font-bold text-brand-700">₹84</div>
                </div>
              </div>
              <div className="mt-5 rounded-2xl bg-brand-600 p-5 text-white text-sm">
                Your driver Ravi is 2 mins away • Wagon R • DL3CAB1234
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Why */}
      <Section
        eyebrow="Why ShareCab"
        title="Built end-to-end for shared short trips."
        intro="ShareCab is not just a booking screen. It includes rider matching, unlocks, fare allocation, OTP verification, driver dispatch flows, realtime trip state, and a documented public demo boundary."
      >
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          <FeatureCard
            icon="₹"
            title="Save on every trip"
            description="Co-riders split the fare with a 30% group discount. Solo trips stay at the regular price — no gotchas."
          />
          <FeatureCard
            icon="◎"
            title="Smart 2–4 km matching"
            description="Pickups within 2 km and drops within 4 km of each other. You barely detour, but you save a lot."
          />
          <FeatureCard
            icon="⏱"
            title="60-second match window"
            description="A draining timer shows how long you have to confirm or reject your match. No surprise commitments."
          />
          <FeatureCard
            icon="🛣"
            title="Real road-following routes"
            description="The map shows the actual driving path with every pickup and drop in order — not a rough straight line."
          />
          <FeatureCard
            icon="📍"
            title="Driver-confirmed arrivals"
            description="Your driver presses a button when they reach your drop — you don't have to remember to. We auto-detect arrival within 80m."
          />
          <FeatureCard
            icon="💬"
            title="In-app chat with co-riders"
            description="Coordinate pickup spots and small details with your matched co-rider — without ever sharing phone numbers."
          />
          <FeatureCard
            icon="✓"
            title="MSG91 OTP flow"
            description="Production OTP uses the MSG91 Flutter widget and backend access-token verification. Local development keeps a gated dev fallback."
          />
          <FeatureCard
            icon="◷"
            title="Payments and ad unlocks"
            description="Riders unlock serious matches through rewarded ads or a Razorpay payment path, with safe test/stub modes for public demos."
          />
          <FeatureCard
            icon="★"
            title="India-first locale"
            description="The apps resolve supported Indian languages for platform UI and place results instead of assuming English-only usage."
          />
        </div>
      </Section>

      <Section
        alt
        eyebrow="Public release"
        title="Source-available, with production boundaries."
        intro="The public repository is designed to be useful for learning and review without exposing provider credentials, live driver operations, KYC details, fraud controls, or safety playbooks."
      >
        <div className="grid lg:grid-cols-3 gap-5">
          <BoundaryCard
            title="Public-functional"
            body="Rider trip planning, destination matching, pricing, ad-watch unlock, payment test/stub flows, and backend state transitions."
          />
          <BoundaryCard
            title="Public-limited"
            body="Driver app source, onboarding UI, subscription surfaces, dispatch screens, and simulated/demo driver flows."
          />
          <BoundaryCard
            title="Private-gated"
            body="Real driver fleet operations, production dispatch, provider credentials, KYC, fraud rules, and sensitive safety operations."
          />
        </div>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link href="/technology" className="btn-primary">Read the technical overview</Link>
          <Link href="/about" className="btn-secondary">Why we built it this way</Link>
        </div>
      </Section>

      {/* CTA */}
      <Section
        eyebrow="Get started"
        title="Your next short ride could cost less."
        intro="Download the app, set your destination, and let us find someone heading the same way."
      >
        <div className="flex flex-col gap-4">
          <AppStoreButtons />
          <Link
            href="/how-it-works"
            className="text-sm font-medium text-brand-700 hover:text-brand-800"
          >
            Or learn how it works →
          </Link>
        </div>
      </Section>
    </>
  );
}

function BoundaryCard({ title, body }: { title: string; body: string }) {
  return (
    <div className="rounded-2xl bg-white border border-ink-300/40 p-6">
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-sm muted leading-relaxed">{body}</p>
    </div>
  );
}

function Row({ dot, label, sub }: { dot?: boolean; label: string; sub: string }) {
  return (
    <div className="flex items-start gap-3">
      <span className={`mt-1 h-2.5 w-2.5 rounded-full ${dot ? 'bg-brand-600' : 'bg-ink-300'}`} />
      <div>
        <div className="text-sm font-semibold">{label}</div>
        <div className="text-xs muted">{sub}</div>
      </div>
    </div>
  );
}
