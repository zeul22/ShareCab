import { ReactNode } from 'react';

export function FeatureCard({
  title,
  description,
  icon,
}: {
  title: string;
  description: string;
  icon?: ReactNode;
}) {
  return (
    <div className="rounded-2xl border border-ink-300/40 bg-white p-6 shadow-sm hover:shadow transition-shadow">
      <div className="h-10 w-10 rounded-xl bg-brand-100 text-brand-700 flex items-center justify-center text-lg">
        {icon ?? '•'}
      </div>
      <h3 className="mt-4 text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-sm muted leading-relaxed">{description}</p>
    </div>
  );
}
