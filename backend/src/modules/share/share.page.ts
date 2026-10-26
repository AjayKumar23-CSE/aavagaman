/** Minimal public tracking page: Leaflet + OSM tiles, polls the JSON view every 5 s. */
export function sharePageHtml(jsonUrl: string, nonce: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Live trip</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style nonce="${nonce}">
  html,body{margin:0;height:100%;font-family:system-ui,sans-serif;background:#f3f4f6;color:#111}
  #map{position:absolute;inset:0 0 120px 0}
  #panel{position:absolute;left:0;right:0;bottom:0;height:120px;background:#fff;border-top:1px solid #e5e7eb;padding:12px 16px;box-sizing:border-box}
  #status{font-weight:600;font-size:18px}
  .muted{color:#6b7280;font-size:14px;margin-top:4px}
</style>
</head>
<body>
<div id="map"></div>
<div id="panel"><div id="status">Loading…</div><div id="driver" class="muted"></div><div id="eta" class="muted"></div></div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script nonce="${nonce}">
(function () {
  var url = ${JSON.stringify(jsonUrl)};
  var map = L.map('map').setView([28.6315, 77.2167], 12);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap' }).addTo(map);
  var car = null, pickup = null, drop = null, fitted = false;
  var LABEL = { REQUESTED: 'Finding a driver', ACCEPTED: 'Driver on the way', ARRIVED: 'Driver has arrived', STARTED: 'Trip in progress',
    COMPLETED: 'Trip completed', PAID: 'Trip completed', CANCELLED: 'Trip cancelled', NO_DRIVER: 'No driver found' };
  function text(id, v) { document.getElementById(id).textContent = v || ''; }
  function refresh() {
    fetch(url, { headers: { accept: 'application/json' } }).then(function (r) { if (!r.ok) throw r; return r.json(); }).then(function (d) {
      text('status', LABEL[d.status] || d.status);
      text('driver', d.driver_name ? d.driver_name + (d.vehicle ? ' · ' + [d.vehicle.colour, d.vehicle.make, d.vehicle.model].filter(Boolean).join(' ') + ' · ' + d.vehicle.reg_number : '') : '');
      text('eta', d.eta_s != null ? 'Arriving in about ' + Math.max(1, Math.round(d.eta_s / 60)) + ' min' : (d.status === 'STARTED' ? 'Heading to ' + d.drop.address : ''));
      if (!pickup) { pickup = L.marker([d.pickup.lat, d.pickup.lng]).addTo(map).bindPopup('Pickup'); drop = L.marker([d.drop.lat, d.drop.lng]).addTo(map).bindPopup('Drop'); }
      if (d.current_location) {
        var ll = [d.current_location.lat, d.current_location.lng];
        if (!car) car = L.circleMarker(ll, { radius: 9, color: '#1e4d8c', fillColor: '#1e4d8c', fillOpacity: 1 }).addTo(map); else car.setLatLng(ll);
        if (!fitted) { map.fitBounds(L.latLngBounds([ll, [d.pickup.lat, d.pickup.lng], [d.drop.lat, d.drop.lng]]), { padding: [40, 40] }); fitted = true; }
      } else if (!fitted) { map.fitBounds(L.latLngBounds([[d.pickup.lat, d.pickup.lng], [d.drop.lat, d.drop.lng]]), { padding: [40, 40] }); fitted = true; }
      if (['COMPLETED', 'PAID', 'CANCELLED', 'NO_DRIVER'].indexOf(d.status) >= 0) clearInterval(timer);
    }).catch(function () { text('status', 'This trip link is not valid'); clearInterval(timer); });
  }
  var timer = setInterval(refresh, 5000);
  refresh();
})();
</script>
</body>
</html>`;
}
