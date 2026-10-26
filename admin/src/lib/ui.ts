/** Shared Tailwind class strings so forms and buttons look the same on every page. */
export const INPUT =
  'w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm focus:border-[#0F3D2E] focus:outline-none disabled:bg-gray-50 disabled:text-gray-400';

export const LABEL = 'mb-1 block text-sm font-medium text-gray-700';

export const BTN_PRIMARY =
  'rounded-md bg-[#0F3D2E] px-4 py-2 text-sm font-medium text-white hover:bg-[#145C45] disabled:opacity-50';

export const BTN_SECONDARY =
  'rounded-md border border-gray-300 bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50';

export const BTN_DANGER =
  'rounded-md border border-red-300 bg-white px-4 py-2 text-sm font-medium text-red-700 hover:bg-red-50 disabled:opacity-50';

export const BTN_SUCCESS =
  'rounded-md bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50';

// Variants are complete class sets: do not append conflicting utilities (two `bg-*` classes resolve by CSS order, not by position).
export const BTN_SMALL = 'rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50';
export const BTN_SMALL_DARK = 'rounded-md border border-[#0F3D2E] bg-[#0F3D2E] px-3 py-1.5 text-sm font-medium text-white hover:bg-[#145C45] disabled:opacity-50';
export const BTN_SMALL_DANGER = 'rounded-md border border-red-300 bg-white px-3 py-1.5 text-sm text-red-700 hover:bg-red-50 disabled:opacity-50';

export const TH = 'px-4 py-3 font-medium';
export const TD = 'px-4 py-3';

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function shortId(id: string | null | undefined): string {
  return id ? id.slice(0, 8) : '—';
}
