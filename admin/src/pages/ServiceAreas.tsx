import { useCallback, useEffect, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { Polygon } from 'geojson';
import L from 'leaflet';
import '@geoman-io/leaflet-geoman-free';
import { useMap } from 'react-leaflet';
import ErrorBanner from '../components/ErrorBanner';
import LeafletMap, { InvalidateOnMount } from '../components/LeafletMap';
import StatusBadge from '../components/StatusBadge';
import { errorMessage } from '../lib/api';
import { createServiceArea, extractPolygon, listServiceAreas, patchServiceArea, type ServiceArea } from '../lib/serviceAreas';
import { formatIST } from '../lib/time';
import { toast } from '../lib/toast';
import { BTN_PRIMARY, BTN_SECONDARY, BTN_SMALL, INPUT, LABEL } from '../lib/ui';

/**
 * A draft is the one editable shape on the map: drawn with the toolbar, imported
 * from a file, or lifted from an existing area via "Edit shape". `initial` is the
 * shape the draft started with and never changes, so the Leaflet layer is built
 * once per draft; `polygon` follows the admin's vertex edits.
 */
interface Draft {
  initial: Polygon;
  polygon: Polygon;
  /** Area whose shape this replaces; null for a new area. */
  forId: string | null;
  source: 'drawn' | 'imported' | 'existing';
}

const vertexCount = (p: Polygon) => Math.max(0, (p.coordinates[0]?.length ?? 1) - 1);

export default function ServiceAreas() {
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ['service-areas'], queryFn: listServiceAreas });
  const areas = query.data?.features ?? [];

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const selected = areas.find((a) => a.properties.id === selectedId) ?? null;
  const [draft, setDraft] = useState<Draft | null>(null);
  const [newName, setNewName] = useState('');
  const [newActive, setNewActive] = useState(true);
  const [rename, setRename] = useState('');
  const [saveError, setSaveError] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['service-areas'] });

  const createMut = useMutation({
    mutationFn: (body: { name: string; polygon: Polygon; active: boolean }) => createServiceArea(body),
    onSuccess: (created) => {
      void invalidate();
      setDraft(null);
      setNewName('');
      setSelectedId(created.properties.id);
      setRename(created.properties.name);
      toast.success(`Service area "${created.properties.name}" created`);
    },
    onError: (e) => setSaveError(errorMessage(e)),
  });
  const patchMut = useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: { name?: string; polygon?: Polygon; active?: boolean } }) => patchServiceArea(id, patch),
    onSuccess: (updated, { patch }) => {
      void invalidate();
      if (patch.polygon) setDraft(null);
      toast.success(
        patch.polygon ? 'Shape saved' : patch.name ? 'Area renamed' : updated.properties.active ? 'Area activated' : 'Area deactivated',
      );
    },
    onError: (e) => setSaveError(errorMessage(e)),
  });

  const startDraft = useCallback((polygon: Polygon, source: Draft['source'], forId: string | null) => {
    setSaveError(null);
    setDraft({ initial: polygon, polygon, forId, source });
  }, []);
  const onDrawn = useCallback((polygon: Polygon) => startDraft(polygon, 'drawn', null), [startDraft]);
  const onDraftEdited = useCallback((polygon: Polygon) => setDraft((d) => (d ? { ...d, polygon } : d)), []);
  const select = useCallback(
    (id: string, name: string) => {
      setSelectedId(id);
      setRename(name);
    },
    [],
  );

  async function importFile(file: File) {
    try {
      const polygon = extractPolygon(JSON.parse(await file.text()));
      startDraft(polygon, 'imported', null);
      if (!newName) setNewName(file.name.replace(/\.(geo)?json$/i, ''));
    } catch (e) {
      toast.error(`Import failed: ${e instanceof Error ? e.message : 'invalid file'}`);
    }
  }

  function saveDraft() {
    if (!draft) return;
    setSaveError(null);
    if (draft.forId) patchMut.mutate({ id: draft.forId, patch: { polygon: draft.polygon } });
    else {
      if (!newName.trim()) {
        setSaveError('Give the new area a name.');
        return;
      }
      createMut.mutate({ name: newName.trim(), polygon: draft.polygon, active: newActive });
    }
  }

  const saving = createMut.isPending || patchMut.isPending;
  const draftTarget = draft?.forId ? areas.find((a) => a.properties.id === draft.forId) : null;

  return (
    <div className="flex h-[calc(100vh-4rem)] flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Service areas</h1>
          <p className="text-sm text-gray-500">Pickups must fall inside an active area. Draw with the map tools or import a GeoJSON polygon.</p>
        </div>
        <div className="flex gap-2">
          <input
            ref={fileInput}
            type="file"
            accept=".json,.geojson,application/geo+json,application/json"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void importFile(f);
              e.target.value = '';
            }}
          />
          <button type="button" onClick={() => fileInput.current?.click()} className={BTN_SECONDARY}>
            Import GeoJSON…
          </button>
        </div>
      </div>

      {query.isError && <ErrorBanner error={query.error} onRetry={() => query.refetch()} />}

      <div className="flex min-h-0 flex-1 gap-4">
        <aside className="flex w-80 shrink-0 flex-col gap-4 overflow-y-auto">
          <section className="rounded-lg border border-gray-200 bg-white">
            <div className="border-b border-gray-200 px-4 py-3 text-sm font-semibold uppercase tracking-wide text-gray-500">Areas</div>
            <ul className="divide-y divide-gray-100">
              {areas.map((a) => (
                <li
                  key={a.properties.id}
                  onClick={() => select(a.properties.id, a.properties.name)}
                  className={`cursor-pointer px-4 py-3 text-sm hover:bg-gray-50 ${a.properties.id === selectedId ? 'bg-gray-50' : ''}`}
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium text-gray-900">{a.properties.name}</span>
                    <StatusBadge status={a.properties.active ? 'active' : 'offline'} />
                  </div>
                  <div className="text-xs text-gray-500">
                    {vertexCount(a.geometry)} vertices{a.properties.created_at && ` · created ${formatIST(a.properties.created_at)}`}
                  </div>
                </li>
              ))}
              {query.isPending && <li className="px-4 py-6 text-center text-sm text-gray-400">Loading…</li>}
              {query.data && areas.length === 0 && <li className="px-4 py-6 text-center text-sm text-gray-500">No service areas yet.</li>}
            </ul>
          </section>

          {selected && !draft && (
            <section className="space-y-3 rounded-lg border border-gray-200 bg-white p-4">
              <div className="text-sm font-semibold uppercase tracking-wide text-gray-500">Selected area</div>
              <label className="block">
                <span className={LABEL}>Name</span>
                <div className="flex gap-2">
                  <input value={rename} onChange={(e) => setRename(e.target.value)} maxLength={60} className={INPUT} />
                  <button
                    type="button"
                    disabled={saving || !rename.trim() || rename.trim() === selected.properties.name}
                    onClick={() => patchMut.mutate({ id: selected.properties.id, patch: { name: rename.trim() } })}
                    className={BTN_SMALL}
                  >
                    Rename
                  </button>
                </div>
              </label>
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  disabled={saving}
                  onClick={() => patchMut.mutate({ id: selected.properties.id, patch: { active: !selected.properties.active } })}
                  className={BTN_SMALL}
                >
                  {selected.properties.active ? 'Deactivate' : 'Activate'}
                </button>
                <button
                  type="button"
                  disabled={saving}
                  onClick={() => startDraft(selected.geometry, 'existing', selected.properties.id)}
                  className={BTN_SMALL}
                >
                  Edit shape
                </button>
              </div>
              {!selected.properties.active && <p className="text-xs text-amber-700">Inactive: pickups here are rejected.</p>}
              {saveError && <p className="rounded-md bg-red-50 px-3 py-2 text-xs text-red-700">{saveError}</p>}
            </section>
          )}

          {draft && (
            <section className="space-y-3 rounded-lg border border-blue-200 bg-blue-50 p-4">
              <div className="text-sm font-semibold uppercase tracking-wide text-blue-800">
                {draft.forId ? `New shape for ${draftTarget?.properties.name ?? 'area'}` : 'New area'}
              </div>
              <p className="text-xs text-blue-900">
                {vertexCount(draft.polygon)} vertices ({draft.source}). Drag a vertex to move it, click a midpoint to add one, right-click a
                vertex to remove it.
              </p>
              {!draft.forId && (
                <>
                  <label className="block">
                    <span className={LABEL}>Name</span>
                    <input autoFocus value={newName} onChange={(e) => setNewName(e.target.value)} maxLength={60} className={INPUT} placeholder="e.g. Gurugram" />
                  </label>
                  <label className="flex items-center gap-2 text-sm text-gray-700">
                    <input type="checkbox" checked={newActive} onChange={(e) => setNewActive(e.target.checked)} />
                    Active immediately
                  </label>
                  {selected && (
                    <button type="button" onClick={() => setDraft({ ...draft, forId: selected.properties.id })} className="text-xs text-blue-800 underline">
                      Use as the new shape of "{selected.properties.name}" instead
                    </button>
                  )}
                </>
              )}
              {saveError && <p className="rounded-md bg-red-50 px-3 py-2 text-xs text-red-700">{saveError}</p>}
              <div className="flex justify-end gap-2">
                <button type="button" disabled={saving} onClick={() => setDraft(null)} className={BTN_SECONDARY}>
                  Discard
                </button>
                <button type="button" disabled={saving} onClick={saveDraft} className={BTN_PRIMARY}>
                  {saving ? 'Saving…' : draft.forId ? 'Save shape' : 'Create area'}
                </button>
              </div>
            </section>
          )}
        </aside>

        <div className="relative min-w-0 flex-1 overflow-hidden rounded-lg border border-gray-200 bg-white">
          <LeafletMap className="h-full w-full">
            <InvalidateOnMount />
            <AreaEditor
              areas={areas}
              selectedId={selectedId}
              hiddenId={draft?.forId ?? null}
              draftInitial={draft?.initial ?? null}
              onSelect={select}
              onDrawn={onDrawn}
              onDraftEdited={onDraftEdited}
            />
          </LeafletMap>
          {!draft && (
            <div className="absolute right-3 bottom-3 z-[400] rounded-md border border-gray-200 bg-white/95 px-3 py-1.5 text-xs text-gray-700">
              Use the polygon or rectangle tool (top left) to draw a new area.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

interface EditorProps {
  areas: ServiceArea[];
  selectedId: string | null;
  /** Area hidden while its replacement shape is being edited. */
  hiddenId: string | null;
  /** Starting shape of the current draft (stable for the draft's lifetime). */
  draftInitial: Polygon | null;
  onSelect: (id: string, name: string) => void;
  onDrawn: (polygon: Polygon) => void;
  onDraftEdited: (polygon: Polygon) => void;
}

/** Imperative Leaflet + Geoman glue; lives inside MapContainer so useMap() works. All callbacks must be stable. */
function AreaEditor({ areas, selectedId, hiddenId, draftInitial, onSelect, onDrawn, onDraftEdited }: EditorProps) {
  const map = useMap();
  const fitted = useRef(false);

  // Toolbar: polygon + rectangle drawing only; editing is per-draft, below.
  useEffect(() => {
    map.pm.setGlobalOptions({ allowSelfIntersection: false, snappable: true, snapDistance: 15 });
    map.pm.addControls({
      position: 'topleft',
      drawMarker: false,
      drawCircleMarker: false,
      drawPolyline: false,
      drawCircle: false,
      drawText: false,
      drawRectangle: true,
      drawPolygon: true,
      editMode: false,
      dragMode: false,
      cutPolygon: false,
      removalMode: false,
      rotateMode: false,
    });
    const onCreate = (e: { layer: L.Layer }) => {
      const gj = (e.layer as L.Polygon).toGeoJSON();
      map.removeLayer(e.layer);
      if (gj.geometry.type === 'Polygon') onDrawn(gj.geometry);
    };
    map.on('pm:create', onCreate);
    return () => {
      map.off('pm:create', onCreate);
      map.pm.removeControls();
    };
  }, [map, onDrawn]);

  // Saved areas (read-only outlines; click selects).
  useEffect(() => {
    const group = L.featureGroup().addTo(map);
    for (const a of areas) {
      if (a.properties.id === hiddenId) continue;
      const sel = a.properties.id === selectedId;
      const layer = L.geoJSON(a.geometry, {
        style: {
          color: a.properties.active ? '#1d4ed8' : '#6b7280',
          weight: sel ? 3 : 1.5,
          dashArray: a.properties.active ? undefined : '6 6',
          fillOpacity: sel ? 0.15 : 0.05,
        },
        pmIgnore: true,
      });
      layer.bindTooltip(a.properties.name, { sticky: true });
      layer.on('click', () => onSelect(a.properties.id, a.properties.name));
      group.addLayer(layer);
    }
    if (!fitted.current && areas.length) {
      fitted.current = true;
      map.fitBounds(group.getBounds(), { padding: [24, 24] });
    }
    return () => {
      group.remove();
    };
  }, [areas, selectedId, hiddenId, map, onSelect]);

  // The editable draft layer; rebuilt only when a new draft starts, not on each vertex edit.
  useEffect(() => {
    if (!draftInitial) return;
    const layer = L.geoJSON(draftInitial, { style: { color: '#dc2626', weight: 3, fillOpacity: 0.12 } }).addTo(map);
    const poly = layer.getLayers()[0] as L.Polygon;
    poly.pm.enable({ allowSelfIntersection: false });
    const emit = () => {
      const gj = poly.toGeoJSON();
      if (gj.geometry.type === 'Polygon') onDraftEdited(gj.geometry);
    };
    poly.on('pm:edit', emit);
    poly.on('pm:vertexremoved', emit);
    map.fitBounds(layer.getBounds(), { padding: [24, 24] });
    return () => {
      poly.pm.disable();
      layer.remove();
    };
  }, [draftInitial, map, onDraftEdited]);

  return null;
}
