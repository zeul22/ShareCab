import { Section } from '@/components/Section';

export const metadata = { title: 'Pricing & savings — ShareCab' };

export default function PricingPage() {
  return (
    <>
      <section className="container-page pt-20 pb-6">
        <h1 className="h-display max-w-3xl">Simple pricing. Real savings.</h1>
        <p className="mt-6 text-lg muted max-w-2xl">
          ShareCab uses a flat fare model: a small base, a per-km rate, and a per-minute rate.
          When you share, the total fare drops, and everyone splits what&rsquo;s left.
        </p>
      </section>

      <Section eyebrow="Fare model" title="The math is straightforward.">
        <div className="grid sm:grid-cols-2 gap-5">
          <Plan
            tag="Solo ride"
            title="Standard fare"
            lines={[
              ['Base fare', '₹30'],
              ['Per km', '₹12'],
              ['Per minute', '₹1'],
            ]}
            footer="Charged exactly as estimated. No surprise surge."
          />
          <Plan
            tag="Shared ride"
            highlighted
            title="Up to 30% off"
            lines={[
              ['Base fare', '₹30 (split)'],
              ['Per km', '₹12 (–30%)'],
              ['Per minute', '₹1 (–30%)'],
            ]}
            footer="If we can't find a co-rider, you ride solo at the standard fare."
          />
        </div>
      </Section>

      <Section
        alt
        eyebrow="Examples"
        title="What a shared ride saves you."
      >
        <div className="grid sm:grid-cols-3 gap-5">
          <Example trip="3 km, 10 min" solo="₹76" shared="₹53" />
          <Example trip="5 km, 15 min" solo="₹105" shared="₹74" />
          <Example trip="8 km, 22 min" solo="₹148" shared="₹104" />
        </div>
        <p className="mt-6 text-sm muted">
          Examples assume two riders sharing. With three riders, savings are even higher.
        </p>
      </Section>
    </>
  );
}

function Plan({
  tag,
  title,
  lines,
  footer,
  highlighted,
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
      <div className={highlighted ? 'text-xs font-semibold uppercase tracking-wider opacity-90' : 'text-xs font-semibold uppercase tracking-wider text-brand-700'}>
        {tag}
      </div>
      <h3 className="mt-2 text-2xl font-semibold">{title}</h3>
      <ul className="mt-5 space-y-2">
        {lines.map(([k, v]) => (
          <li key={k} className={highlighted ? 'flex justify-between text-sm opacity-95' : 'flex justify-between text-sm text-ink-700'}>
            <span>{k}</span>
            <span className="font-semibold">{v}</span>
          </li>
        ))}
      </ul>
      <p className={highlighted ? 'mt-6 text-xs opacity-90' : 'mt-6 text-xs muted'}>{footer}</p>
    </div>
  );
}

function Example({ trip, solo, shared }: { trip: string; solo: string; shared: string }) {
  return (
    <div className="rounded-2xl bg-white border border-ink-300/40 p-6">
      <div className="text-xs muted uppercase tracking-wider">Trip</div>
      <div className="text-lg font-semibold">{trip}</div>
      <div className="mt-4 flex items-end justify-between">
        <div>
          <div className="text-xs muted">Solo</div>
          <div className="text-base line-through opacity-70">{solo}</div>
        </div>
        <div className="text-right">
          <div className="text-xs text-brand-700 font-semibold">Shared</div>
          <div className="text-2xl font-bold text-brand-700">{shared}</div>
        </div>
      </div>
    </div>
  );
}
