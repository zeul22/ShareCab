import { ReactNode } from 'react';

export function Section({
  eyebrow,
  title,
  intro,
  children,
  alt,
}: {
  eyebrow?: string;
  title: string;
  intro?: string;
  children?: ReactNode;
  alt?: boolean;
}) {
  return (
    <section className={alt ? 'section bg-brand-50/40' : 'section'}>
      <div className="container-page">
        <div className="max-w-2xl">
          {eyebrow && (
            <div className="text-xs font-semibold uppercase tracking-wider text-brand-700">
              {eyebrow}
            </div>
          )}
          <h2 className="mt-2 h-section">{title}</h2>
          {intro && <p className="mt-4 text-lg muted">{intro}</p>}
        </div>
        {children && <div className="mt-12">{children}</div>}
      </div>
    </section>
  );
}
