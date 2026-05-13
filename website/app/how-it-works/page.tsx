import { Section } from '@/components/Section';

export const metadata = { title: 'How it works — ShareCab' };

const steps = [
  {
    title: 'Sign in with OTP',
    text: 'Production uses the MSG91 Flutter OTP widget and backend access-token verification. Local demo mode can use a clearly gated dev OTP fallback.',
  },
  {
    title: 'Set pickup, drop, and luggage',
    text: 'Pick your pickup point and destination on the map. Tell us how much luggage you have so we don’t pair you with riders whose bags won’t fit.',
  },
  {
    title: 'Unlock matching',
    text: 'Watch rewarded ads, or pay a small one-shot unlock fee through Razorpay. Public demo mode can use test/stub providers while preserving the same backend state transitions.',
  },
  {
    title: 'Confirm your match in 60 seconds',
    text: 'See your co-rider’s first name, rating, and detour cost. A draining timer shows how long you have to confirm or reject. If you don’t act, we auto-reject — no surprise commitments.',
  },
  {
    title: 'Driver picks you both up',
    text: 'The map shows the actual driving path through every stop in order — not a straight line. Chat with your co-rider in-app to coordinate the exact pickup spot, no phone numbers exchanged.',
  },
  {
    title: 'Driver confirms each drop',
    text: 'When the driver reaches your destination, their app auto-detects arrival within 80m and they confirm the drop with one tap. Your trip ends — you don’t have to remember to press anything.',
  },
  {
    title: 'Pay your share, rate the ride',
    text: 'You pay only your part of the discounted fare. Then rate the driver and your co-rider. Two-way ratings keep ShareCab safe and friendly.',
  },
];

export default function HowItWorksPage() {
  return (
    <>
      <section className="container-page pt-20 pb-6">
        <h1 className="h-display max-w-3xl">How ShareCab works</h1>
        <p className="mt-6 text-lg muted max-w-2xl">
          Seven steps from sign-in to drop. No complicated rules. No surprises.
        </p>
      </section>

      <Section eyebrow="The flow" title="From sign-in to drop, in seven steps.">
        <ol className="space-y-5">
          {steps.map((s, i) => (
            <li key={s.title} className="flex gap-5 rounded-2xl border border-ink-300/40 bg-white p-6">
              <div className="h-10 w-10 shrink-0 rounded-full bg-brand-600 text-white flex items-center justify-center font-semibold">
                {i + 1}
              </div>
              <div>
                <h3 className="text-lg font-semibold">{s.title}</h3>
                <p className="mt-1 text-sm muted leading-relaxed">{s.text}</p>
              </div>
            </li>
          ))}
        </ol>
      </Section>

      <Section
        alt
        eyebrow="Behind the scenes"
        title="Matching tuned for short trips."
        intro="ShareCab’s engine is built specifically for city trips. We look at pickup proximity, drop proximity, and detour cost. We don’t pair you with riders going far out of the way — even if it saves more on paper."
      >
        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-5">
          <Metric title="Pickup radius" value="2 km" />
          <Metric title="Drop radius" value="4 km" />
          <Metric title="Max riders" value="3" />
          <Metric title="Demo mode" value="Rider-first" />
        </div>
        <p className="mt-6 text-sm muted max-w-3xl">
          The public source release keeps rider-side planning, matching, pricing,
          unlocks, and trip state functional. Real production driver dispatch is
          gated behind private configuration so demo builds do not connect to live
          driver operations.
        </p>
      </Section>
    </>
  );
}

function Metric({ title, value }: { title: string; value: string }) {
  return (
    <div className="rounded-2xl bg-white border border-ink-300/40 p-6">
      <div className="text-xs font-semibold uppercase tracking-wider text-brand-700">{title}</div>
      <div className="mt-2 text-2xl font-semibold">{value}</div>
    </div>
  );
}
