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
              Cheaper rides for short trips
            </div>
            <h1 className="mt-5 h-display">
              Share the cab.<br />
              <span className="text-brand-600">Split the fare.</span>
            </h1>
            <p className="mt-6 text-lg muted max-w-xl">
              ShareCab matches you with riders going within 2–4 km of your destination,
              so you save on every short trip without giving up convenience.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Link href="/how-it-works" className="btn-primary">See how it works</Link>
              <Link href="/pricing" className="btn-secondary">View pricing</Link>
            </div>
            <div className="mt-10 flex items-center gap-6 text-sm muted">
              <div><span className="font-semibold text-ink-900">30%+</span> typical savings</div>
              <div><span className="font-semibold text-ink-900">2 min</span> avg wait</div>
              <div><span className="font-semibold text-ink-900">4.8★</span> driver rating</div>
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
        title="Designed for short city trips."
        intro="Most cab rides are under 8 km. Our matching is tuned for this — quick, nearby, and almost always shareable."
      >
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          <FeatureCard
            icon="₹"
            title="Save on every trip"
            description="Riders heading near you split the fare. Typical savings range from 25–40% on short trips."
          />
          <FeatureCard
            icon="◎"
            title="Smart 2–4 km matching"
            description="We pair pickups within 2 km and drops within 4 km — you barely detour, but you save a lot."
          />
          <FeatureCard
            icon="⌛"
            title="Quick to match"
            description="Most rides match in under a minute. If we can't find a co-rider, you ride solo at the regular price."
          />
          <FeatureCard
            icon="✓"
            title="Verified drivers"
            description="All ShareCab drivers are background-verified, with vehicle and license checks."
          />
          <FeatureCard
            icon="◷"
            title="Live tracking"
            description="Watch your cab in real time. Share your trip with friends and family in one tap."
          />
          <FeatureCard
            icon="★"
            title="Two-way ratings"
            description="Riders and drivers rate every trip. Bad actors don't last on the platform."
          />
        </div>
      </Section>

      {/* CTA */}
      <Section
        alt
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
