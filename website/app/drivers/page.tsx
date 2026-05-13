import Link from 'next/link';
import { Section } from '@/components/Section';
import { FeatureCard } from '@/components/FeatureCard';

export const metadata = {
  title: 'For drivers — ShareCab',
  description:
    'No per-ride commission. ₹199/month flat subscription. First month free. Keep more of every fare with ShareCab.',
};

export default function DriversPage() {
  return (
    <>
      {/* Hero */}
      <section className="relative">
        <div className="container-page pt-20 pb-12 sm:pt-28 sm:pb-16 grid lg:grid-cols-2 gap-12 items-center">
          <div>
            <div className="inline-flex items-center gap-2 rounded-full border border-brand-200 bg-brand-50 px-3 py-1 text-xs font-medium text-brand-700">
              For drivers
            </div>
            <h1 className="mt-5 h-display">
              Keep <span className="text-brand-600">100%</span> of every fare.
            </h1>
            <p className="mt-6 text-lg muted max-w-xl">
              ShareCab is designed around zero per-ride commission and a flat subscription
              model. The public source release shows the driver flow, while real production
              driver operations remain gated.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Link href="/contact" className="btn-primary">Sign up as a driver</Link>
              <Link href="#economics" className="btn-secondary">See the math</Link>
            </div>
            <div className="mt-10 flex items-center gap-6 text-sm muted">
              <div><span className="font-semibold text-ink-900">0%</span> per-ride commission</div>
              <div><span className="font-semibold text-ink-900">₹199</span>/month flat</div>
              <div><span className="font-semibold text-ink-900">30 days</span> free trial</div>
            </div>
          </div>

          <div className="relative">
            <div className="aspect-[4/5] rounded-3xl bg-gradient-to-br from-brand-100 via-white to-brand-50 border border-brand-200/60 p-6 shadow-xl">
              <div className="rounded-2xl bg-white p-5 shadow-sm">
                <div className="text-xs font-semibold uppercase tracking-wider text-brand-700">
                  Subscription
                </div>
                <div className="mt-3 flex items-end justify-between">
                  <div>
                    <div className="text-3xl font-bold text-brand-700">₹199</div>
                    <div className="text-xs muted">per month</div>
                  </div>
                  <div className="rounded-full bg-brand-50 border border-brand-200 px-3 py-1 text-xs font-semibold text-brand-700">
                    First month FREE
                  </div>
                </div>
                <div className="mt-4 h-px bg-ink-300/30" />
                <div className="mt-4 text-xs muted">Renews monthly via Razorpay. Cancel anytime.</div>
              </div>

              <div className="mt-5 rounded-2xl bg-white p-5 shadow-sm">
                <div className="text-xs font-semibold uppercase tracking-wider text-brand-700">
                  Commission
                </div>
                <div className="mt-3 text-3xl font-bold">0%</div>
                <div className="mt-1 text-xs muted">on every ride, every fare, every rider</div>
              </div>

              <div className="mt-5 rounded-2xl bg-brand-600 p-5 text-white">
                <div className="text-xs uppercase tracking-wider opacity-90">Active dispatch</div>
                <div className="mt-2 text-base font-semibold">2 active riders</div>
                <div className="text-xs opacity-90">Total fare to collect: ₹240</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Why */}
      <Section
        eyebrow="Why drivers stay"
        title="A simpler, fairer deal."
        intro="Most platforms take a percentage from every ride. ShareCab's model keeps the driver economics predictable: flat subscription, OTP pickup verification, clear dispatch state, and no hidden per-ride cut."
      >
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          <FeatureCard
            icon="₹"
            title="0% per-ride cut"
            description="Whatever the rider pays, you keep 100%. No platform fee on individual fares — just the flat monthly subscription."
          />
          <FeatureCard
            icon="📅"
            title="30-day free trial"
            description="Sign up, drive for a full month, see how it actually performs in your area before you pay anything."
          />
          <FeatureCard
            icon="🚖"
            title="Shared rides = more per trip"
            description="One trip can carry 2–3 riders, and you charge for all of them. Same kilometres, more income."
          />
          <FeatureCard
            icon="📍"
            title="Geofence auto-arrival"
            description="The app detects when you're within 80m of any pickup or drop and surfaces a one-tap confirm — no scrolling stop lists."
          />
          <FeatureCard
            icon="🛣"
            title="Real road-following routes"
            description="Turn-by-turn directions through every pickup and drop in optimal order. Built on Google Directions, not approximations."
          />
          <FeatureCard
            icon="💳"
            title="No surprises on subscription"
            description="₹199 charged via Razorpay (UPI / cards / netbanking). Renew when you want; renewing early extends, never resets, your expiry."
          />
        </div>
      </Section>

      {/* Economics */}
      <Section
        alt
        eyebrow="Public release boundary"
        title="Driver source is visible; live driver ops are protected."
        intro="The driver app is part of the public source release for review, UI work, and local demo testing. Connecting real drivers, production dispatch, KYC, fleet quality controls, and safety operations requires private production configuration."
      >
        <div className="grid sm:grid-cols-3 gap-5">
          <Need title="Visible in public">
            Driver login, onboarding screens, subscription surfaces, dispatch UI, active trip
            route, location push code, and pickup OTP flow.
          </Need>
          <Need title="Demo only by default">
            Public builds can use simulated drivers and rider-side demos. Backend demo mode blocks
            production driver dispatch unless explicitly enabled.
          </Need>
          <Need title="Private in production">
            KYC providers, app signing, live dispatch, real driver supply, provider secrets, and
            sensitive safety operations.
          </Need>
        </div>
      </Section>

      <Section
        id="economics"
        eyebrow="The math"
        title="Why this works for both sides."
        intro="At ~30 rides/day at an average ₹200 fare, here's roughly what each model leaves you with at the end of the month."
      >
        <div className="grid sm:grid-cols-2 gap-5">
          <Plan
            tag="Typical app"
            title="20% commission per ride"
            lines={[
              ['Gross fares (30 × ₹200 × 30 days)', '₹1,80,000'],
              ['Platform commission (20%)', '−₹36,000'],
              ['You keep', '₹1,44,000'],
            ]}
            footer="Every fare you take leaks 1/5 to the platform — every day, every month, every year."
          />
          <Plan
            tag="ShareCab"
            highlighted
            title="Flat ₹199/month"
            lines={[
              ['Gross fares (30 × ₹200 × 30 days)', '₹1,80,000'],
              ['ShareCab subscription', '−₹199'],
              ['You keep', '₹1,79,801'],
            ]}
            footer="₹35,801/month more in your pocket vs the typical commission model. Tax-deductible, predictable."
          />
        </div>
        <p className="mt-6 text-sm muted">
          Numbers are illustrative — your actual fare mix and ride density will vary. The structural
          difference (per-ride cut vs flat fee) is the same regardless of volume.
        </p>
      </Section>

      {/* What you need */}
      <Section
        eyebrow="What you need"
        title="To start driving on ShareCab."
      >
        <div className="grid sm:grid-cols-2 gap-5">
          <Need title="Documents">
            Valid driving licence · vehicle RC · commercial permit (if your state requires one) ·
            insurance · PAN.
          </Need>
          <Need title="Vehicle">
            Hatchback, sedan, or SUV in roadworthy condition. We do a quick inspection during onboarding.
          </Need>
          <Need title="Phone">
            Android or iOS smartphone with GPS. The driver app uses location during active trips
            to power geofence arrival detection.
          </Need>
          <Need title="Payment method">
            Bank account for fare settlement (riders pay you directly, no platform escrow) and
            UPI / card / netbanking for the ₹199 subscription auto-renewal.
          </Need>
        </div>
      </Section>

      {/* CTA */}
      <Section
        alt
        eyebrow="Get on the road"
        title="Ready to keep more of what you earn?"
        intro="Sign up, pass a quick verification, and your first month is free."
      >
        <div className="flex flex-col gap-4">
          <div className="flex flex-wrap gap-3">
            <Link href="/contact" className="btn-primary">Sign up as a driver</Link>
            <Link href="/safety" className="btn-secondary">How we keep it safe</Link>
          </div>
          <p className="text-xs muted">
            Subscription gates only the “go online” switch — you can install the app, complete
            verification, and review riders without paying. Charged only when you flip online.
          </p>
        </div>
      </Section>
    </>
  );
}

function Plan({
  tag, title, lines, footer, highlighted,
}: {
  tag: string;
  title: string;
  lines: [string, string][];
  footer: string;
  highlighted?: boolean;
}) {
  return (
    <div
      className={
        highlighted
          ? 'rounded-2xl bg-brand-600 text-white p-6 shadow-lg'
          : 'rounded-2xl bg-white border border-ink-300/40 p-6'
      }
    >
      <div className={highlighted
        ? 'text-xs font-semibold uppercase tracking-wider opacity-90'
        : 'text-xs font-semibold uppercase tracking-wider text-brand-700'}>
        {tag}
      </div>
      <h3 className="mt-2 text-2xl font-semibold">{title}</h3>
      <ul className="mt-5 space-y-2">
        {lines.map(([k, v]) => (
          <li
            key={k}
            className={highlighted
              ? 'flex justify-between text-sm opacity-95'
              : 'flex justify-between text-sm text-ink-700'}
          >
            <span>{k}</span>
            <span className="font-semibold">{v}</span>
          </li>
        ))}
      </ul>
      <p className={highlighted ? 'mt-6 text-xs opacity-90' : 'mt-6 text-xs muted'}>{footer}</p>
    </div>
  );
}

function Need({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl bg-white border border-ink-300/40 p-6">
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-sm muted leading-relaxed">{children}</p>
    </div>
  );
}
