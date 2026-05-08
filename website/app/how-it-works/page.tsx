import { Section } from '@/components/Section';

export const metadata = { title: 'How it works — ShareCab' };

const steps = [
  {
    title: 'Set your destination',
    text: 'Open the app, pick your pickup point and destination. Toggle “share to save” on (it’s on by default).',
  },
  {
    title: 'We find a match nearby',
    text: 'Our matching engine looks for riders whose destinations are within 2–4 km of yours and pickups within 2 km.',
  },
  {
    title: 'Driver comes to both of you',
    text: 'A nearby driver picks you up first, then your co-rider — or both of you at the same point.',
  },
  {
    title: 'Pay only your share',
    text: 'You pay only your part of the discounted fare. Drivers earn the same — we just route smarter.',
  },
  {
    title: 'Rate the ride',
    text: 'After drop, rate your driver and your co-rider. Two-way ratings keep ShareCab safe and friendly.',
  },
];

export default function HowItWorksPage() {
  return (
    <>
      <section className="container-page pt-20 pb-6">
        <h1 className="h-display max-w-3xl">How ShareCab works</h1>
        <p className="mt-6 text-lg muted max-w-2xl">
          Five simple steps from booking to drop. No complicated rules. No surprises.
        </p>
      </section>

      <Section eyebrow="The flow" title="Five simple steps.">
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
      />
    </>
  );
}
