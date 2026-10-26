import { useState } from 'react';
import Modal from '../../components/Modal';
import { errorMessage } from '../../lib/api';
import { FUEL_TYPES, VEHICLE_TYPES, type FuelType, type Vehicle, type VehiclePatch } from '../../lib/drivers';

interface Props {
  vehicle: Vehicle;
  onSave: (patch: VehiclePatch) => Promise<unknown>;
  onClose: () => void;
}

type Form = Record<keyof Required<VehiclePatch>, string>;

const TEXT_FIELDS: { key: 'reg_number' | 'make' | 'model' | 'colour'; label: string; max: number }[] = [
  { key: 'reg_number', label: 'Registration no.', max: 13 },
  { key: 'make', label: 'Make', max: 40 },
  { key: 'model', label: 'Model', max: 40 },
  { key: 'colour', label: 'Colour', max: 30 },
];

const DATE_FIELDS: { key: 'insurance_expiry' | 'permit_expiry' | 'fitness_expiry'; label: string }[] = [
  { key: 'insurance_expiry', label: 'Insurance expiry' },
  { key: 'permit_expiry', label: 'Permit expiry' },
  { key: 'fitness_expiry', label: 'Fitness expiry' },
];

const INPUT = 'w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-gray-900 focus:outline-none';

function toForm(v: Vehicle): Form {
  return {
    reg_number: v.reg_number,
    make: v.make,
    model: v.model,
    colour: v.colour,
    fuel_type: v.fuel_type,
    vehicle_type: v.vehicle_type,
    insurance_expiry: v.insurance_expiry ?? '',
    permit_expiry: v.permit_expiry ?? '',
    fitness_expiry: v.fitness_expiry ?? '',
  };
}

export default function VehicleEditDialog({ vehicle, onSave, onClose }: Props) {
  const initial = toForm(vehicle);
  const [form, setForm] = useState<Form>(initial);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = (key: keyof Form, value: string) => setForm((f) => ({ ...f, [key]: value }));

  async function submit(e: { preventDefault(): void }) {
    e.preventDefault();
    // Only send changed, non-empty fields (the API cannot clear a value).
    const patch: Record<string, string> = {};
    for (const key of Object.keys(form) as (keyof Form)[]) {
      const value = form[key].trim();
      if (value && value !== initial[key]) patch[key] = value;
    }
    if (Object.keys(patch).length === 0) {
      onClose();
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await onSave(patch as VehiclePatch);
      onClose();
    } catch (err) {
      setError(errorMessage(err));
      setBusy(false);
    }
  }

  return (
    <Modal title="Edit vehicle" onClose={onClose} busy={busy}>
      <form onSubmit={submit} className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          {TEXT_FIELDS.map((f) => (
            <label key={f.key} className="block">
              <span className="mb-1 block text-sm font-medium text-gray-700">{f.label}</span>
              <input
                value={form[f.key]}
                maxLength={f.max}
                required
                onChange={(e) => set(f.key, e.target.value)}
                {...(f.key === 'reg_number' && { pattern: '[A-Za-z0-9 \\-]{6,13}', title: '6–11 letters and digits' })}
                className={`${INPUT} ${f.key === 'reg_number' ? 'font-mono uppercase' : ''}`}
              />
            </label>
          ))}
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-gray-700">Fuel type</span>
            <select
              value={form.fuel_type}
              onChange={(e) => set('fuel_type', e.target.value as FuelType)}
              className={`${INPUT} bg-white uppercase`}
            >
              {FUEL_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </label>
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-gray-700">Vehicle type</span>
            <select value={form.vehicle_type} onChange={(e) => set('vehicle_type', e.target.value)} className={`${INPUT} bg-white capitalize`}>
              {VEHICLE_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
            <span className="mt-1 block text-xs text-gray-400">Which ride requests this driver receives.</span>
          </label>
          {DATE_FIELDS.map((f) => (
            <label key={f.key} className="block">
              <span className="mb-1 block text-sm font-medium text-gray-700">{f.label}</span>
              <input type="date" value={form[f.key]} onChange={(e) => set(f.key, e.target.value)} className={INPUT} />
            </label>
          ))}
        </div>
        {error && <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
        <div className="flex justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            disabled={busy}
            className="rounded-md border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={busy}
            className="rounded-md bg-[#0F3D2E] px-4 py-2 text-sm font-medium text-white hover:bg-[#145C45] disabled:opacity-50"
          >
            {busy ? 'Saving…' : 'Save'}
          </button>
        </div>
      </form>
    </Modal>
  );
}
