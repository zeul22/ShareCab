import { env } from '@/lib/env';

type Props = {
  variant?: 'primary' | 'inline';
  className?: string;
};

export function AppStoreButtons({ variant = 'primary', className = '' }: Props) {
  return (
    <div className={`flex flex-wrap gap-3 ${className}`}>
      <StoreLink
        href={env.appStoreUrl}
        label="Download on the"
        platform="App Store"
        variant={variant}
        Icon={AppleIcon}
      />
      <StoreLink
        href={env.playStoreUrl}
        label="Get it on"
        platform="Google Play"
        variant={variant}
        Icon={PlayIcon}
      />
    </div>
  );
}

function StoreLink({
  href,
  label,
  platform,
  variant,
  Icon,
}: {
  href: string;
  label: string;
  platform: string;
  variant: 'primary' | 'inline';
  Icon: React.ComponentType<{ className?: string }>;
}) {
  const enabled = href.length > 0;
  const baseDark =
    'inline-flex items-center gap-3 rounded-2xl bg-ink-900 text-white px-5 py-3 hover:bg-ink-700 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-400';
  const baseInline =
    'inline-flex items-center gap-3 rounded-xl border border-ink-300/60 bg-white px-4 py-2.5 hover:border-brand-300 hover:bg-brand-50 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-400';
  const cls = variant === 'primary' ? baseDark : baseInline;
  const disabled = 'opacity-60 cursor-not-allowed';

  const content = (
    <>
      <Icon className="h-7 w-7 shrink-0" />
      <span className="leading-tight text-left">
        <span className="block text-[10px] uppercase tracking-wider opacity-80">
          {enabled ? label : 'Coming soon —'}
        </span>
        <span className="block text-sm font-semibold">{platform}</span>
      </span>
    </>
  );

  if (!enabled) {
    return (
      <span className={`${cls} ${disabled}`} aria-disabled="true">
        {content}
      </span>
    );
  }

  return (
    <a href={href} target="_blank" rel="noreferrer" className={cls}>
      {content}
    </a>
  );
}

function AppleIcon({ className = '' }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M16.365 1.43c0 1.14-.42 2.235-1.247 3.14-.85.93-2.247 1.65-3.385 1.557-.13-1.114.443-2.262 1.21-3.07.84-.89 2.288-1.54 3.422-1.627zM20.5 17.21c-.41.95-.6 1.376-1.13 2.214-.74 1.17-1.78 2.626-3.07 2.638-1.146.012-1.44-.745-2.99-.737-1.55.008-1.873.75-3.02.738-1.29-.012-2.275-1.327-3.015-2.498-2.07-3.27-2.286-7.107-1.01-9.147.91-1.452 2.347-2.302 3.696-2.302 1.376 0 2.24.755 3.376.755 1.103 0 1.776-.756 3.367-.756 1.205 0 2.483.66 3.394 1.802-2.984 1.636-2.498 5.9.402 7.293z" />
    </svg>
  );
}

function PlayIcon({ className = '' }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <path d="M3.6 1.94c-.36.27-.6.7-.6 1.23v17.66c0 .53.24.96.6 1.23l9.86-10.06L3.6 1.94z" fill="#34A853" />
      <path d="M17.62 8.84 13.46 12l4.16 4.16 4.27-2.43c1-.57 1-2.04 0-2.62l-4.27-2.27z" fill="#FBBC04" />
      <path d="m13.46 12-9.86 10.06c.43.32 1.04.36 1.56.07L17.62 15.16 13.46 12z" fill="#EA4335" />
      <path d="M3.6 1.94 13.46 12l4.16-3.16L5.16 1.87c-.52-.29-1.13-.25-1.56.07z" fill="#4285F4" />
    </svg>
  );
}
