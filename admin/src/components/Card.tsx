import type { ReactNode } from 'react';

interface Props {
  title: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
  /** Removes the inner padding, for tables and maps that fill the card. */
  flush?: boolean;
}

export default function Card({ title, action, children, className = '', flush }: Props) {
  return (
    <section className={`rounded-lg border border-gray-200 bg-white ${flush ? '' : 'p-5'} ${className}`}>
      <div className={`flex items-center justify-between ${flush ? 'border-b border-gray-200 px-5 py-3' : 'mb-4'}`}>
        <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}

export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <dt className="text-xs text-gray-500">{label}</dt>
      <dd className="text-sm text-gray-900">{children ?? '—'}</dd>
    </div>
  );
}
